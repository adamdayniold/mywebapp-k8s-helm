#!/bin/bash
set -e

flux bootstrap git \
  --url=ssh://git@github.com/adamdayniold/mywebapp-k8s-helm.git \
  --branch=main \
  --path=clusters/local-orbstack