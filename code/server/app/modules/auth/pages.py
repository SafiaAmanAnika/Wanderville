"""Small browser landing pages for account email links; no client credentials."""
from html import escape

from fastapi.responses import HTMLResponse


def account_page(title, message, form=""):
    return HTMLResponse(
        "<!doctype html><html lang='en'><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{escape(title)} · Wanderville</title>"
        "<style>body{max-width:32rem;margin:10vh auto;padding:2rem;background:#382617;"
        "color:#f2e8cc;font:18px system-ui}input,button{display:block;padding:.8rem;"
        "margin:1rem 0;width:100%;box-sizing:border-box}button{cursor:pointer}</style>"
        f"<h1>{escape(title)}</h1><p id='status'>{escape(message)}</p>{form}</html>",
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff"},
    )


def reset_page():
    return account_page("Reset password", "Choose a new Wanderville password.", """
<form id="reset"><label for="password">New password</label>
<input id="password" type="password" minlength="8" maxlength="128" required autocomplete="new-password">
<label for="confirm">Confirm password</label>
<input id="confirm" type="password" minlength="8" maxlength="128" required autocomplete="new-password">
<button>Save password</button></form>
<script>
const token = new URLSearchParams(location.search).get('token');
history.replaceState(null, '', location.pathname);
document.getElementById('reset').addEventListener('submit', async event => {
  event.preventDefault();
  const form = event.target, status = document.getElementById('status');
  const password = document.getElementById('password').value;
  if (password !== document.getElementById('confirm').value) {
    status.textContent = 'Passwords do not match.'; return;
  }
  form.querySelector('button').disabled = true;
  try {
    const response = await fetch('/auth/reset-password', {method: 'POST',
      headers: {'Content-Type': 'application/json'}, body: JSON.stringify({token, new_password: password})});
    const result = await response.json();
    status.textContent = result.message || 'Unable to reset password.';
    if (response.ok) form.hidden = true;
  } catch { status.textContent = 'Connection failed. Please try again.'; }
  form.querySelector('button').disabled = false;
});
</script>""")
