#!/bin/bash
#
# Copyright 2017 - Adriano Pezzuto
# https://github.com/kalise
#
gcloud compute instances list --filter="name=$(hostname)"
