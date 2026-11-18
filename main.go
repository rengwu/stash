// xsaves keeps a local copy of your X bookmarks and likes.
//
//	xsaves                  open the window
//	xsaves sync [--login]   fetch new saves; --login may show a sign-in window
//	xsaves schedule on|off  fetch new saves every six hours in the background
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	webview "github.com/webview/webview_go"
)

func main() {
	var err error
	switch arg := append(os.Args[1:], "", "")[:2]; arg[0] {
	case "":
		err = runWindow()
	case "sync":
		err = runSync(arg[1] == "--login")
	case "schedule":
		err = setSchedule(arg[1] == "on")
	default:
		err = fmt.Errorf("usage: xsaves [sync [--login] | schedule on|off]")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func runWindow() error {
	db, err := openStore()
	if err != nil {
		return err
	}
	defer db.Close()
	addr, err := serve(db)
	if err != nil {
		return err
	}
	w := webview.New(false)
	defer w.Destroy()
	w.SetTitle("xsaves")
	w.SetSize(1200, 860, webview.HintNone)
	// Links to x.com open in the default browser, not inside the app.
	w.Bind("openExternal", func(url string) {
		if strings.HasPrefix(url, "https://") {
			exec.Command("open", url).Start()
		}
	})
	// Verification hook: a script to run in the page, used to drive the UI in checks.
	if js := os.Getenv("XSAVES_EVAL"); js != "" {
		w.Init("addEventListener('load', () => setTimeout(() => {" + js + "}, 1500))")
	}
	w.Navigate(addr)
	w.Run()
	return nil
}

const agent = "com.xsaves.sync"

func agentPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "LaunchAgents", agent+".plist")
}

func scheduled() bool {
	_, err := os.Stat(agentPath())
	return err == nil
}

// setSchedule installs or removes a launchd agent that runs "xsaves sync"
// every six hours, whether or not the window is open.
func setSchedule(on bool) error {
	domain := fmt.Sprint("gui/", os.Getuid())
	exec.Command("launchctl", "bootout", domain+"/"+agent).Run() // absent is fine
	if !on {
		if err := os.Remove(agentPath()); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	log := filepath.Join(dataDir(), "sync.log")
	plist := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>Label</key><string>%s</string>
	<key>ProgramArguments</key><array><string>%s</string><string>sync</string></array>
	<key>StartInterval</key><integer>21600</integer>
	<key>StandardOutPath</key><string>%s</string>
	<key>StandardErrorPath</key><string>%s</string>
</dict></plist>
`, agent, exe, log, log)
	if err := os.MkdirAll(filepath.Dir(agentPath()), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(agentPath(), []byte(plist), 0o644); err != nil {
		return err
	}
	if out, err := exec.Command("launchctl", "bootstrap", domain, agentPath()).CombinedOutput(); err != nil {
		os.Remove(agentPath())
		return fmt.Errorf("launchctl: %s", strings.TrimSpace(string(out)))
	}
	return nil
}
