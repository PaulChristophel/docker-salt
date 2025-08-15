//go:build !windows
// +build !windows

package main

import (
	"golang.org/x/term"
)

func isTerminal(fd uintptr) bool {
	return term.IsTerminal(int(fd))
}

func readPasswordNoEcho(fd uintptr) ([]byte, error) {
	return term.ReadPassword(int(fd))
}
