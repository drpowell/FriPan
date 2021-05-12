#!/bin/sh

echo "Run: make compile"
echo "      (or 'make debug' for development)"
echo "http://localhost:8030/pan.html"
python -m $(python -c 'import sys; print("http.server" if sys.version_info[:2] > (2,7) else "SimpleHTTPServer")') 8030


