#!/bin/bash
# Fetch all new tags and push them to the mirror
# Fetch all specified branches (their name must be the same on both the mirror and upstream)
pwd=$(git rev-parse --abbrev-ref HEAD)
target=$(cat trackedbranch)
remote="https://android.googlesource.com/kernel/build"

if ! git diff-index --quiet HEAD --; then
  echo "- Stashing unsaved changes"
  git stash
  pop=1
fi
echo

echo "- Fetching"
git remote add upstream $remote -f --tags | grep -v "new branch"
echo
for branch in $target; do
  echo "- Updating $branch"
  git -c advice.detachedHead=false checkout -f upstream/$branch
  git push origin HEAD:$branch
  echo
done

git checkout $pwd --quiet
echo "- Updating tags..."
git push origin --tags
echo

if [[ -n $pop ]] ; then
  echo "- Restoring changes"
  git stash pop
fi