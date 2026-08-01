#!/bin/bash

# restructure_billions.sh
# Safely moves ripped disc files into Jellyfin-compliant naming.
# Never deletes anything — source disc folders remain after rename.
# Dry-run by default. Pass --run to execute.

set -euo pipefail

RIPPED_BASE="/Users/hippolytebuisson/Movies/Ripped"
MOVIES_BASE="${RIPPED_BASE}/Billions (2016)"
META="${MOVIES_BASE}/.metadata"

# --- Configuration ---