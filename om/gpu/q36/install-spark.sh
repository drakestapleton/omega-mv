#!/bin/sh
# Install the pure seeded-Omega Zero-CUDA Qwen 3.6 35B-A3B + Arboris package on DGX Spark.
# Installs binaries into ~/.local/opt/q36/, launchers into ~/.local/bin/{q36-35b,q36-serve},
# writes ~/.local/opt/q36/manifest.json, and wires ~/.config/systemd/user/motor-revival.service.
set -eu

repo_dir=${1:-.}
opt_dir="$HOME/.local/opt/q36"
bin_dir="$HOME/.local/bin"
model_dir="${Q36_MODEL_DIR:-$HOME/models/qwen3.6-35b-a3b-fp8-95a723d0}"
svc_dir="$HOME/.config/systemd/user"
svc_file="$svc_dir/motor-revival.service"

mkdir -p "$opt_dir" "$bin_dir"
(cd "$repo_dir" && sh om/gpu/q36/build.sh "$opt_dir")

sha_serve=$(sha256sum "$opt_dir/q36-serve" | awk '{print $1}')
sha_decode=$(sha256sum "$opt_dir/q36-decode" | awk '{print $1}')
sha_head=$(sha256sum "$opt_dir/q36-head" | awk '{print $1}')
sha_native=$(sha256sum "$opt_dir/q36-native" | awk '{print $1}')
commit_sha=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || echo "unknown")

cat > "$opt_dir/manifest.json" <<EOF
{
  "package": "q36-35b-omega-arboris",
  "model": "qwen3.6-35b-a3b-fp8",
  "context_window": 131072,
  "default_precision": "w4",
  "arboris_enabled": true,
  "zero_cuda": true,
  "commit": "$commit_sha",
  "model_dir": "$model_dir",
  "binaries": {
    "q36-serve": "$sha_serve",
    "q36-decode": "$sha_decode",
    "q36-head": "$sha_head",
    "q36-native": "$sha_native"
  }
}
EOF

cat > "$bin_dir/q36-35b" <<EOF
#!/bin/sh
# Pure seeded-Omega Zero-CUDA Qwen 3.6 35B-A3B + Live Arboris launcher (Full-W4 default, --fp8 optional).
exec "$opt_dir/q36-serve" --model-dir "\${Q36_MODEL_DIR:-$model_dir}" "\$@"
EOF
chmod +x "$bin_dir/q36-35b"
ln -sf "$opt_dir/q36-serve" "$bin_dir/q36-serve"
ln -sf "$opt_dir/q36-decode" "$bin_dir/q36-decode"

if [ -d "$svc_dir" ]; then
  if [ -f "$svc_file" ] && [ ! -f "$svc_file.bak-pre-q36-omega" ]; then
    cp "$svc_file" "$svc_file.bak-pre-q36-omega"
  fi
  cat > "$svc_file" <<EOF
[Unit]
Description=Qwen 3.6 35B-A3B Pure Seeded-Omega Zero-CUDA Server + Live Arboris (Full-W4 default)
After=network.target

[Service]
Type=simple
ExecStart=$opt_dir/q36-serve --model-dir $model_dir --port 18091
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload 2>/dev/null || true
fi

echo "INSTALLED q36-35b-omega-arboris -> $opt_dir"
echo "  q36-serve : $sha_serve"
echo "  q36-decode: $sha_decode"
echo "  launcher  : $bin_dir/q36-35b (Full-W4 default + Live Arboris, --fp8 optional)"
echo "  service   : $svc_file (port 18091)"
