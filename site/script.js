// Copy buttons only. The page works without JS: every command is plain text.
document.querySelectorAll('#install button[data-copy]').forEach(function (btn) {
  var label = btn.textContent;
  var status = document.getElementById('copy-status');
  var what = (btn.getAttribute('aria-label') || '').replace(/^Copy command: /, '');
  var say = function (text) {
    if (!status) { return; }
    status.textContent = text;
    setTimeout(function () { status.textContent = ''; }, 1500);
  };
  btn.addEventListener('click', function () {
    var done = function () {
      btn.textContent = 'Copied';
      say('Copied: ' + what);
      setTimeout(function () { btn.textContent = label; }, 1500);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(btn.getAttribute('data-copy')).then(done, select);
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
