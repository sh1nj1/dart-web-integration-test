#!/bin/bash

# BFG를 사용하여 chrome과 chromedriver 디렉토리를 git 히스토리에서 완전히 제거

echo "=== Git History Cleanup ==="
echo "This will remove chrome/ and chromedriver/ from all git history"
echo ""

# Confirm
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

echo ""
echo "Step 1: Remove folders from git history using BFG..."
bfg --delete-folders chrome
bfg --delete-folders chromedriver

echo ""
echo "Step 2: Cleanup and garbage collect..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo ""
echo "Step 3: Force push required to update remote repository"
echo "Run: git push origin --force --all"
echo ""
echo "Done! Repository size should be significantly reduced."
