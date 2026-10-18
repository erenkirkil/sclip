#!/usr/bin/env bash
# --options runtime yalnizca yorumda geciyor, komutta yok.
codesign --force --sign "$IDENTITY" dist/sclip.app
