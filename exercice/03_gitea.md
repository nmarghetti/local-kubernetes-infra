# Gitea

Lets setup a git server, add a repository and push in it.

```shell
# this will fail
docker run -it --rm -p 9093:3000 -p 9094:22 gitea/gitea gitea

docker run -u git -e DB_TYPE=sqlite3 -it --rm -p 9093:3000 -p 9094:22 -v ./tmp/gitea:/data gitea/gitea gitea
```

- visit <http://localhost:9093/>
- select `SQLite3` as database type
- at the bottom, add an administrator account: gitadmin
- click on `Install gitea`
- add `local_cluster` repository

```shell
git remote add some-gitea http://localhost:9093/gitadmin/local_cluster.git
git push some-gitea main
```

If you want, you can setup a token or a ssh key to connect to the git server more safely.

```shell
# clean up
git remote remove some-gitea
rm -rf tmp/gitea
```
