package main

import (
	"encoding/json"
	"os/exec"
	"strings"
	"testing"
)

func TestGenerateHashAndVerify(t *testing.T) {
	password := "myS3cretP@ss"

	// Generate hash
	hash, err := generateHash(password)
	if err != nil {
		t.Fatalf("generateHash failed: %v", err)
	}

	if !strings.HasPrefix(hash, "$y$") {
		t.Errorf("unexpected hash prefix: %s", hash)
	}

	// Verify hash (should succeed)
	ok, err := verifyHash(password, hash)
	if err != nil {
		t.Errorf("verifyHash returned error: %v", err)
	}
	if !ok {
		t.Errorf("expected verification to succeed, got false")
	}
}

func TestVerifyHashFailsOnWrongPassword(t *testing.T) {
	password := "correctpassword"
	hash, err := generateHash(password)
	if err != nil {
		t.Fatalf("generateHash failed: %v", err)
	}

	// Try verifying with incorrect password
	ok, err := verifyHash("wrongpassword", hash)
	if err != nil {
		t.Errorf("verifyHash returned error on wrong password: %v", err)
	}
	if ok {
		t.Errorf("expected verification to fail with wrong password, got true")
	}
}

func TestVerifyHashFailsOnBadHash(t *testing.T) {
	_, err := verifyHash("any", "$notarealhash$")
	if err == nil {
		t.Error("expected error with malformed hash, got nil")
	}
}

func TestGenerateSaltLengthAndCharset(t *testing.T) {
	salt, err := generateSalt(16)
	if err != nil {
		t.Fatalf("generateSalt failed: %v", err)
	}
	if len(salt) != 16 {
		t.Errorf("expected salt length 16, got %d", len(salt))
	}
	const charset = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	for _, c := range salt {
		if !strings.ContainsRune(charset, c) {
			t.Errorf("invalid salt character: %q", c)
		}
	}
}

func TestInvalidModeCLI(t *testing.T) {
	cmd := exec.Command("./yescrypt-cli", "--mode=bogus")
	out, err := cmd.CombinedOutput()

	if err == nil {
		t.Error("expected non-zero exit code for invalid mode")
	}

	var res result
	if jerr := json.Unmarshal(out, &res); jerr != nil {
		t.Fatalf("failed to parse JSON output: %v\nOutput: %s", jerr, out)
	}

	if res.Error == "" || !strings.Contains(res.Error, "invalid mode") {
		t.Errorf("expected 'invalid mode' error, got: %q", res.Error)
	}
}

func TestVerifyMissingArgs(t *testing.T) {
	_, err := verifyHash("", "")
	if err == nil {
		t.Error("expected error when verifying with empty password and hash")
	}
}
