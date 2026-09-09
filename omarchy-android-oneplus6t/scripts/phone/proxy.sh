# Optional escape hatch for a phone with no network of its own.
#
# Run `ssh -N -R 1080 <user>@<phone-ip>` on the host and it exposes a SOCKS5
# proxy on the phone's localhost:1080; pacman (libcurl), git and curl all honour
# these variables. Before Wi-Fi is joined this is the only route out.
#
# Only set them when that tunnel is actually up. Once the phone has a connection
# of its own, an unconditional proxy would send every request into a dead port
# and package installs would fail with the network apparently working.
if (exec 3<>/dev/tcp/127.0.0.1/1080) 2>/dev/null; then
  exec 3<&- 3>&-
  export http_proxy=socks5h://127.0.0.1:1080
  export https_proxy=socks5h://127.0.0.1:1080
  export ALL_PROXY=socks5h://127.0.0.1:1080
  export HTTP_PROXY=$http_proxy HTTPS_PROXY=$https_proxy
  export no_proxy=localhost,127.0.0.1
fi
