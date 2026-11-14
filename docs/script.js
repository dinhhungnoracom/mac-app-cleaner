document.addEventListener('DOMContentLoaded', () => {
  // Checksum Accordion Toggle
  const checksumToggle = document.getElementById('checksumToggle');
  const checksumContent = document.getElementById('checksumContent');

  if (checksumToggle && checksumContent) {
    checksumToggle.addEventListener('click', () => {
      const isHidden = checksumContent.classList.contains('hidden');
      checksumContent.classList.toggle('hidden');
      const arrow = checksumToggle.querySelector('.arrow-icon');
      if (arrow) {
        arrow.textContent = isHidden ? '▴' : '▾';
      }
    });
  }

  // Copy Checksum buttons
  document.querySelectorAll('.btn-copy').forEach((btn) => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-target');
      const codeEl = document.getElementById(targetId);
      if (codeEl) {
        const text = codeEl.textContent.trim();
        navigator.clipboard.writeText(text).then(() => {
          const original = btn.textContent;
          btn.textContent = 'Đã copy!';
          btn.style.color = '#34d399';
          setTimeout(() => {
            btn.textContent = original;
            btn.style.color = '';
          }, 2000);
        });
      }
    });
  });

  // Interactive Window Tab Toggle
  const tabAppsBtn = document.getElementById('tabAppsBtn');
  const tabTrashBtn = document.getElementById('tabTrashBtn');
  const tabMonitorBtn = document.getElementById('tabMonitorBtn');
  const previewTabApps = document.getElementById('previewTabApps');
  const previewTabTrash = document.getElementById('previewTabTrash');
  const previewTabMonitor = document.getElementById('previewTabMonitor');

  function selectTab(selectedBtn, selectedView) {
    [tabAppsBtn, tabTrashBtn, tabMonitorBtn].forEach((b) => b?.classList.remove('active'));
    [previewTabApps, previewTabTrash, previewTabMonitor].forEach((v) => v?.classList.add('hidden'));
    selectedBtn?.classList.add('active');
    selectedView?.classList.remove('hidden');
  }

  tabAppsBtn?.addEventListener('click', () => selectTab(tabAppsBtn, previewTabApps));
  tabTrashBtn?.addEventListener('click', () => selectTab(tabTrashBtn, previewTabTrash));
  tabMonitorBtn?.addEventListener('click', () => selectTab(tabMonitorBtn, previewTabMonitor));
});
