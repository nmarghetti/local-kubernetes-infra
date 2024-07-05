# Docker container

You need to create `container.env` file:

```shell
# if you already have your DISPLAY var setup:
echo "export DISPLAY=$DISPLAY" > container.env

# if you have xserver.sh
xserver.sh | grep -i display > container.env

# if you have hostserver.sh
echo "DISPLAY=$(hostserver.sh -f):0" > container.env

# Otherwise just create it yourself and put the following content
# eg. DISPLAY=192.168.0.10:0
export DISPLAY=<PUT YOUR XSERVER ADDRESS AND PORT>
```

You also need the `.Xauthority` file if your xserver is secured:

```shell
cp "$HOME"/.Xauthority .
```
