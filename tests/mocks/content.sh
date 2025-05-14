#!/bin/bash
# Mock content detection module

# Get content type from file extension
detect_content_type() {
    local file="$1"
    local ext="${file##*.}"
    
    case "$ext" in
        txt) echo "text/plain" ;;
        md)  echo "text/markdown" ;;
        html|htm) echo "text/html" ;;
        json) echo "application/json" ;;
        xml) echo "application/xml" ;;
        csv) echo "text/csv" ;;
        pdf) echo "application/pdf" ;;
        jpg|jpeg) echo "image/jpeg" ;;
        png) echo "image/png" ;;
        gif) echo "image/gif" ;;
        mp4) echo "video/mp4" ;;
        mov) echo "video/quicktime" ;;
        zip) echo "application/zip" ;;
        docx) echo "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ;;
        xlsx) echo "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ;;
        pptx) echo "application/vnd.openxmlformats-officedocument.presentationml.presentation" ;;
        *) echo "application/octet-stream" ;;
    esac
}