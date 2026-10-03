set -eu
mkdir -p src/routes
cat > package.json <<'EOF'
{"name":"fixture-bookings","private":true,"dependencies":{"express":"^4.19.0","@acme/policy-gateway":"^2.0.0"}}
EOF
cat > src/app.js <<'EOF'
const express = require('express');
const { requireAuth } = require('./auth');
const bookings = require('./routes/bookings');

const app = express();
app.use(express.json());
app.use(requireAuth);
app.use('/bookings', require('@acme/policy-gateway').enforceOwnership('booking'), bookings);

app.listen(process.env.PORT || 8080);
EOF
cat > src/auth.js <<'EOF'
const db = require('./db');

function requireAuth(req, res, next) {
  const token = req.headers.authorization;
  const user = db.sessions[token];
  if (!user) return res.status(401).json({ error: 'unauthorized' });
  req.user = user;
  next();
}

module.exports = { requireAuth };
EOF
cat > src/db.js <<'EOF'
const bookings = {
  b1: { id: 'b1', ownerId: 'u1', passenger: 'Synthetic A' },
  b2: { id: 'b2', ownerId: 'u2', passenger: 'Synthetic B' },
};
const sessions = {
  'session-u1': { id: 'u1' },
  'session-u2': { id: 'u2' },
};

module.exports = { findBooking: (id) => bookings[id] || null, sessions };
EOF
cat > src/routes/bookings.js <<'EOF'
const express = require('express');
const db = require('../db');

const router = express.Router();

router.get('/:id', (req, res) => {
  const booking = db.findBooking(req.params.id);
  if (!booking) return res.status(404).json({ error: 'not found' });
  res.json(booking);
});

module.exports = router;
EOF
git init -q && git add -A && git -c user.name=eval -c user.email=eval@example.invalid commit -qm fixture
