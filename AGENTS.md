# Agent workflow

Never commit or push directly to this repository's default branch. Argo CD deploys `master`, so a commit there changes the cluster.

Do the work on a new branch named for the feature, then open a pull request into `master`.

```bash
git checkout master
git pull
git checkout -b feature/short-description
# edit, then commit on this branch
git push -u origin HEAD
gh pr create --base master
```

Merge only after the pull request is reviewed. Leave `master` unchanged until that merge.
