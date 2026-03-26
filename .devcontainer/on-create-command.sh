#!/bin/bash

set -e

sudo apt-get update && sudo apt-get install golang-go -y

GOPATH="$HOME/go" go install golang.org/x/tools/gopls@latest