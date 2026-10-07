#!/usr/bin/env python3
"""Print only non-secret target assertions for the authorized backend task."""
import json
from proxy import load_credentials

config = load_credentials()
allowed = ('expected_hostname', 'database', 'organization', 'tenant')
print(json.dumps({key: config[key] for key in allowed}))
