set -eu
mkdir -p src
cat > package.json <<'EOF'
{"name":"fixture-slugify","private":true,"main":"src/slugify.js"}
EOF
cat > src/slugify.js <<'EOF'
function slugify(text) {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, '-');
}

module.exports = { slugify };
EOF
cat > README.md <<'EOF'
A tiny pure slug helper.
EOF
git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.invalid commit -qm fixture
