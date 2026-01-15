#!/bin/bash
cd "$(dirname "$0")"

# Producer 패키징
mkdir -p producer_pkg
pip3 install -r requirements.txt -t producer_pkg/
cp producer.py producer_pkg/
cd producer_pkg && zip -r ../producer.zip . && cd ..

# Consumer 패키징
mkdir -p consumer_pkg
cp consumer.py consumer_pkg/
cd consumer_pkg && zip -r ../consumer.zip . && cd ..

rm -rf producer_pkg consumer_pkg
echo "Done: producer.zip, consumer.zip"
