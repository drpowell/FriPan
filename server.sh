#!/bin/sh

echo "Run: make compile"
echo "      (or 'make debug' for development)"
echo "http://localhost:8030/pan.html"
python -mSimpleHTTPServer 8030

