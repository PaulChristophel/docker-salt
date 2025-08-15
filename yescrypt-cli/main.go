package main

import (
	"bufio"
	"crypto/rand"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	yescrypt "github.com/openwall/yescrypt-go"
)

type result struct {
	Mode     string `json:"mode"`
	Password string `json:"password,omitempty"`
	Hash     string `json:"hash,omitempty"`
	Valid    bool   `json:"valid,omitempty"`
	Error    string `json:"error,omitempty"`
}

func generateSalt(length int) (string, error) {
	const b64Chars = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	buf := make([]byte, length)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	out := make([]byte, length)
	for i := 0; i < length; i++ {
		out[i] = b64Chars[int(buf[i])%len(b64Chars)]
	}
	return string(out), nil
}

func generateHash(password string) (string, error) {
	salt, err := generateSalt(16)
	if err != nil {
		return "", err
	}
	setting := "$y$j9T$" + salt
	hash, err := yescrypt.Hash([]byte(password), []byte(setting))
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func verifyHash(password, hash string) (bool, error) {
	if !strings.HasPrefix(hash, "$y$") {
		return false, errors.New("invalid yescrypt hash format")
	}
	newHash, err := yescrypt.Hash([]byte(password), []byte(hash))
	if err != nil {
		return false, fmt.Errorf("hashing error: %w", err)
	}
	return string(newHash) == hash, nil
}

func readPasswordFromStdin() (string, error) {
	fmt.Fprint(os.Stderr, "Enter password (input hidden): ")
	// fall back to basic reader if not on a terminal
	if !isTerminal(os.Stdin.Fd()) {
		reader := bufio.NewReader(os.Stdin)
		pass, err := reader.ReadString('\n')
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(pass), nil
	}

	// Use syscall/terminal only if stdin is a terminal
	passBytes, err := readPasswordNoEcho(os.Stdin.Fd())
	if err != nil {
		return "", err
	}
	fmt.Fprintln(os.Stderr) // newline after prompt
	return string(passBytes), nil
}

func main() {
	random := flag.Bool("random", false, "Generate and hash a random password")
	mode := flag.String("mode", "generate", "Mode: generate or verify")
	pass := flag.String("password", "", "Password to hash or verify (or read from stdin if omitted)")
	hash := flag.String("hash", "", "Existing hash (for verify mode)")

	flag.Usage = func() {
		if _, err := fmt.Fprintf(flag.CommandLine.Output(), "Usage:\n  %[1]s -mode [generate|verify] [--password <pw>] [--hash <hash>]\n\nFlags:\n", os.Args[0]); err != nil {
			fmt.Fprintln(os.Stderr, "failed to write usage:", err)
		}
		flag.PrintDefaults()
	}
	flag.Parse()
	if *random {
		pwd, err := generateSalt(16)
		res := result{Mode: "generate", Password: pwd}
		if err != nil {
			res.Error = err.Error()
		} else {
			h, err := generateHash(pwd)
			if err != nil {
				res.Error = err.Error()
			} else {
				res.Hash = h
			}
		}
		output, _ := json.MarshalIndent(res, "", "  ")
		fmt.Println(string(output))
		if res.Error != "" {
			os.Exit(1)
		}
		return
	}

	var res result
	res.Mode = *mode

	switch *mode {
	case "generate":
		pwd := *pass
		if pwd == "" {
			var err error
			pwd, err = readPasswordFromStdin()
			if err != nil {
				res.Error = "failed to read password from stdin: " + err.Error()
				break
			}
		}
		res.Password = pwd
		h, err := generateHash(pwd)
		if err != nil {
			res.Error = "failed to generate hash: " + err.Error()
			break
		}
		res.Hash = h

	case "verify":
		if *pass == "" {
			var err error
			*pass, err = readPasswordFromStdin()
			if err != nil {
				res.Error = "failed to read password from stdin: " + err.Error()
				break
			}
		}
		if *hash == "" {
			res.Error = "missing --hash for verification"
			break
		}
		ok, err := verifyHash(*pass, *hash)
		if err != nil {
			res.Error = "verification failed: " + err.Error()
			break
		}
		res.Valid = ok

	default:
		res.Error = "invalid mode; must be 'generate' or 'verify'"
	}

	output, _ := json.MarshalIndent(res, "", "  ")
	fmt.Println(string(output))

	if res.Error != "" {
		os.Exit(1)
	}
}
