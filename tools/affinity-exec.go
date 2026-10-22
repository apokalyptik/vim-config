// Copyright 2026 vim-config contributors. MIT licence; see affinity-exec.LICENSE.
//go:build linux && amd64

// affinity-exec restricts the executed program to one already-permitted CPU.
// It reduces CPU-sized worker pools; it does not impose an OS-thread limit.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"syscall"
	"unsafe"
)

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "vim-config affinity-exec: "+format+"\n", args...)
	os.Exit(1)
}

func main() {
	if len(os.Args) < 2 || !filepath.IsAbs(os.Args[1]) {
		fail("usage: affinity-exec /absolute/program [args...]")
	}
	// Linux affinity belongs to an OS thread. Exec must run on the same locked
	// thread whose affinity was changed; exec removes the other runtime threads.
	runtime.LockOSThread()
	var permitted [1024]byte // CPU ids 0..8191; reject larger kernel masks clearly.
	size, _, errno := syscall.RawSyscall(syscall.SYS_SCHED_GETAFFINITY, 0,
		uintptr(len(permitted)), uintptr(unsafe.Pointer(&permitted[0])))
	if errno != 0 {
		fail("cannot read permitted CPU affinity: %v", errno)
	}
	if size == 0 || size > uintptr(len(permitted)) {
		fail("kernel returned invalid CPU affinity mask size %d", size)
	}
	var selected [1024]byte
	found := false
	for index := uintptr(0); index < size; index++ {
		bits := permitted[index]
		if bits != 0 {
			selected[index] = bits & -bits
			found = true
			break
		}
	}
	if !found {
		fail("no permitted CPU in affinity mask")
	}
	_, _, errno = syscall.RawSyscall(syscall.SYS_SCHED_SETAFFINITY, 0,
		size, uintptr(unsafe.Pointer(&selected[0])))
	if errno != 0 {
		fail("cannot restrict CPU affinity to one permitted CPU: %v", errno)
	}
	if err := syscall.Exec(os.Args[1], os.Args[1:], os.Environ()); err != nil {
		fail("cannot execute %s: %v", os.Args[1], err)
	}
}
