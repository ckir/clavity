// Copy buttons only. The page works without JS: every command is plain text.
document.querySelectorAll('#install button[data-copy]').forEach(function (btn) {
  var label = btn.textContent;
  btn.addEventListener('click', function () {
    var done = function () {
      btn.textContent = 'Copied';
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
      var range = document.createRange();
      range.selectNodeContents(code);
      var sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    }
  });
});
