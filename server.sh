#!/bin/sh

echo "Run: coffee -c -w . &"
echo "http://localhost:8030/pan.html"
python -mSimpleHTTPServer 8030

