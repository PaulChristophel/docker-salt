package main

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
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
		return false, err
	}
	return string(newHash) == hash, nil
}

func main() {
	mode := flag.String("mode", "generate", "Mode: generate or verify")
	pass := flag.String("password", "", "Password to hash or verify")
	hash := flag.String("hash", "", "Existing hash (for verify mode)")
	flag.Parse()

	var res result
	switch *mode {
	case "generate":
		res.Mode = "generate"
		pwd := *pass
		if pwd == "" {
			random, err := generateSalt(16)
			if err != nil {
				res.Error = err.Error()
				break
			}
			pwd = random
		}
		res.Password = pwd
		h, err := generateHash(pwd)
		if err != nil {
			res.Error = err.Error()
			break
		}
		res.Hash = h

	case "verify":
		res.Mode = "verify"
		if *pass == "" || *hash == "" {
			res.Error = "both --password and --hash are required in verify mode"
			break
		}
		ok, err := verifyHash(*pass, *hash)
		if err != nil {
			res.Error = err.Error()
			break
		}
		res.Valid = ok

	default:
		res.Error = "invalid mode; must be 'generate' or 'verify'"
	}

	output, _ := json.MarshalIndent(res, "", "  ")
	fmt.Println(string(output))
}
