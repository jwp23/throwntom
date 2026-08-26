// Command tomctl drives a running throwntomd over its unix socket.
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/jwp23/throwntom/v3/internal/core"
)

const baseURL = "http://throwntomd"

func main() {
	socket := flag.String("socket", "", "daemon socket path (default: ~/.config/throwntom/daemon.sock)")
	flag.Usage = func() { _, _ = fmt.Fprint(os.Stderr, usage) }
	flag.Parse()
	path := *socket
	if path == "" {
		paths, err := core.DefaultPaths()
		if err != nil {
			_, _ = fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		path = paths.Socket
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	os.Exit(runWithContext(ctx, flag.Args(), os.Stdout, os.Stderr, newUnixClient(path), baseURL))
}

const usage = `usage: tomctl [--socket path] <state|events|cmd <line...>>
  state    print the daemon state document
  events   stream state documents, one JSON object per line, until interrupted
  cmd      run a throwntom command line (e.g. tomctl cmd task add "write tests")
`

func newUnixClient(socket string) *http.Client {
	return &http.Client{Transport: &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", socket)
		},
	}}
}

func run(args []string, stdout, stderr io.Writer, client *http.Client, base string) int {
	return runWithContext(context.Background(), args, stdout, stderr, client, base)
}

func runWithContext(ctx context.Context, args []string, stdout, stderr io.Writer, client *http.Client, base string) int {
	if len(args) == 0 {
		_, _ = fmt.Fprint(stderr, usage)
		return 2
	}
	var err error
	switch args[0] {
	case "state":
		err = printState(ctx, stdout, client, base)
	case "events":
		err = streamEvents(ctx, stdout, client, base)
	case "cmd":
		err = runCommand(ctx, stdout, client, base, strings.Join(args[1:], " "))
	default:
		_, _ = fmt.Fprint(stderr, usage)
		return 2
	}
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

func printState(ctx context.Context, out io.Writer, client *http.Client, base string) error {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+"/v1/state", nil)
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	var pretty bytes.Buffer
	if err := json.Indent(&pretty, raw, "", "  "); err != nil {
		return err
	}
	_, err = fmt.Fprintln(out, pretty.String())
	return err
}

func streamEvents(ctx context.Context, out io.Writer, client *http.Client, base string) error {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+"/v1/events", nil)
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	scanner := bufio.NewScanner(resp.Body)
	for scanner.Scan() {
		if line := scanner.Text(); strings.HasPrefix(line, "data: ") {
			_, _ = fmt.Fprintln(out, strings.TrimPrefix(line, "data: "))
		}
	}
	if ctx.Err() != nil {
		return nil
	}
	return scanner.Err()
}

func runCommand(ctx context.Context, out io.Writer, client *http.Client, base, line string) error {
	body, _ := json.Marshal(map[string]string{"line": line})
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, base+"/v1/command", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	var payload struct {
		Message string `json:"message"`
		Error   string `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return err
	}
	if payload.Error != "" {
		return fmt.Errorf("%s", payload.Error)
	}
	if payload.Message != "" {
		_, _ = fmt.Fprintln(out, payload.Message)
	}
	return nil
}
