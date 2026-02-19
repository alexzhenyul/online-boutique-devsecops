#!/bin/bash
set -x  # prints each command before running
sh jenkins.sh
sh aws.sh
sh docker.sh
sh kubectl.sh
sh eksctl.sh
sh terraform.sh
sh trivy.sh