'use strict';

const comparison = document.querySelector('#film-comparison');
const range = document.querySelector('#comparison-range');
const value = document.querySelector('#comparison-value');
if (comparison && range && value) {
  const updateComparison = () => {
    comparison.style.setProperty('--split', `${range.value}%`);
    value.textContent = `${range.value}%`;
    range.setAttribute('aria-valuetext', `${range.value}% Framer finish revealed`);
  };
  range.addEventListener('input', updateComparison);
  updateComparison();
  document.querySelector('.comparison-controls').hidden = false;
}

const status = document.querySelector('#copy-status');
for (const button of document.querySelectorAll('[data-copy]')) {
  const code = document.getElementById(button.dataset.copy);
  if (!code) continue;
  button.hidden = false;
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = 'Copied';
      status.textContent = 'Command copied to clipboard.';
      window.setTimeout(() => { button.textContent = 'Copy'; }, 2000);
    } catch {
      const selection = window.getSelection();
      const selectedCode = document.createRange();
      selectedCode.selectNodeContents(code);
      selection.removeAllRanges();
      selection.addRange(selectedCode);
      status.textContent = 'Copy was unavailable. The command is selected; use your keyboard copy shortcut.';
    }
  });
}

// Keep horizontally scrolling command blocks reachable by keyboard.
for (const pre of document.querySelectorAll('pre')) pre.tabIndex = 0;
