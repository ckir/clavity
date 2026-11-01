/**
 * Copyright (c) 2026 Costas Kirgoussios
 *
 * This software is licensed under the PolyForm Noncommercial License 1.0.0.
 * You may obtain a copy of the License at:
 * https://polyformproject.org/licenses/noncommercial/1.0.0/
 */

// Copy buttons only. The page works without JS: every command is plain text.
var statusTimers = [];
document.querySelectorAll('#install button[data-copy]').forEach(function (btn) {
  var label = btn.textContent;
  var status = document.getElementById('copy-status');
  var what = (btn.getAttribute('aria-label') || '').replace(/^Copy command: /, '');
  var cmd = btn.getAttribute('data-copy');

  var say = function (text) {
    if (!status) { return; }
    statusTimers.forEach(clearTimeout);
    status.textContent = '';
    statusTimers = [
      setTimeout(function () { status.textContent = text; }, 50),
      setTimeout(function () { status.textContent = ''; }, 1550)
    ];
  };

  btn.addEventListener('click', function () {
    var done = function () {
      btn.textContent = 'Copied';
      say('Copied: ' + what);
      if (window.ClavityAnalytics) {
        window.ClavityAnalytics.track('install_command_copied', { command: cmd });
      }
      setTimeout(function () { btn.textContent = label; }, 1500);
    };

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(cmd).then(done, select);
    } else {
      select();
    }

    function select() {
      var code = btn.parentElement.querySelector('code');
      if (!code) { return; }
      say('Selected for copying: press Ctrl+C. ' + what);
      var range = document.createRange();
      range.selectNodeContents(code);
      var sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    }
  });
});

// Beta registration form handler (for /beta/)
(function () {
  var form = document.getElementById('beta-intake-form');
  if (!form) { return; }

  var statusDiv = document.getElementById('form-status');
  var submitBtn = document.getElementById('form-submit-btn');
  var hasStarted = false;

  form.addEventListener('focusin', function () {
    if (!hasStarted) {
      hasStarted = true;
      if (window.ClavityAnalytics) {
        window.ClavityAnalytics.track('beta_form_started', { form_id: 'beta-intake-form' });
      }
    }
  });

  var commCheckbox = document.getElementById('commercial-interest');
  if (commCheckbox) {
    commCheckbox.addEventListener('change', function () {
      if (commCheckbox.checked && window.ClavityAnalytics) {
        window.ClavityAnalytics.track('commercial_interest_selected', {});
      }
    });
  }

  form.addEventListener('submit', function (e) {
    e.preventDefault();

    var email = (document.getElementById('email') || {}).value || '';
    var role = (document.getElementById('role') || {}).value || '';
    var privacy = (document.getElementById('privacy') || {}).checked;
    var commercial = commCheckbox ? commCheckbox.checked : false;

    // Reset status
    if (statusDiv) {
      statusDiv.className = 'status-msg';
      statusDiv.textContent = '';
    }

    // Validation
    var emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email.trim())) {
      showError('Please enter a valid developer email address.');
      return;
    }
    if (!role) {
      showError('Please select whether you are an individual developer or team.');
      return;
    }
    if (!privacy) {
      showError('Please acknowledge the privacy agreement to continue.');
      return;
    }

    // Collect components
    var components = [];
    document.querySelectorAll('input[name="components"]:checked').forEach(function (cb) {
      components.push(cb.value);
    });

    var payload = {
      email: email.trim(),
      role: role,
      components: components,
      commercialInterest: commercial,
      submittedAt: new Date().toISOString()
    };

    // Track analytics (sanitized, zero-PII)
    if (window.ClavityAnalytics) {
      window.ClavityAnalytics.track('beta_form_submitted', {
        role_type: role,
        has_commercial_interest: commercial,
        component_count: components.length
      });
    }

    // Backend dispatch check
    var endpoint = form.getAttribute('data-endpoint') || window.__CLAVITY_BETA_ENDPOINT__;

    if (endpoint) {
      submitBtn.disabled = true;
      submitBtn.textContent = 'Submitting...';

      fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
      .then(function (res) {
        if (!res.ok) { throw new Error('Server returned ' + res.status); }
        return res.json();
      })
      .then(function () {
        showSuccess('Registration confirmed! Check your inbox for onboarding details.');
        form.reset();
      })
      .catch(function (err) {
        showError('Unable to connect to submission service: ' + err.message + '. Please use GitHub Discussions.');
      })
      .finally(function () {
        submitBtn.disabled = false;
        submitBtn.textContent = 'Submit Beta Interest';
      });
    } else {
      // Documented development placeholder when no backend webhook is configured
      showSuccess('Interest recorded (Preview Mode)! Backend webhook is not configured yet. Please also join us on GitHub Discussions.');
      form.reset();
    }
  });

  function showError(msg) {
    if (!statusDiv) { return; }
    statusDiv.className = 'status-msg error';
    statusDiv.setAttribute('role', 'alert');
    statusDiv.textContent = msg;
  }

  function showSuccess(msg) {
    if (!statusDiv) { return; }
    statusDiv.className = 'status-msg success';
    statusDiv.setAttribute('role', 'status');
    statusDiv.textContent = msg;
  }
})();
