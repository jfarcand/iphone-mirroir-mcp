// ABOUTME: Declarative obstacle injector — reads a page's `#obstacles` JSON block and shows modals.
// ABOUTME: Mirrors the iOS simulator's obstacle shape (id/title/body/buttons/trigger) in plain JS.
//
// A page declares its obstacles as JSON:
//
//   <script type="application/json" id="obstacles">
//   [{ "id": "cookie-consent", "title": "We use cookies",
//      "body": "…", "buttons": ["Accept", "Reject"],
//      "trigger": "on_first_load" }]
//   </script>
//
// Triggers:
//   "on_first_load"          fire once, as soon as the page is interactive
//   { "after_clicks": <n> }  fire once the visitor has clicked <n> elements
//   "never"                  declared for documentation; never injected
//
// Tapping any button dismisses the modal permanently for that page load.
(() => {
  const source = document.getElementById('obstacles');
  if (!source) return;

  let specs;
  try {
    specs = JSON.parse(source.textContent);
  } catch (err) {
    console.error('obstacle.js: malformed #obstacles JSON', err);
    return;
  }

  const pending = specs.filter((spec) => spec.trigger !== 'never');
  let clicks = 0;

  const render = (spec) => {
    const overlay = document.createElement('div');
    overlay.className = 'obstacle-overlay';
    overlay.setAttribute('data-test', `obstacle-${spec.id}`);

    const modal = document.createElement('div');
    modal.className = 'obstacle-modal';

    const title = document.createElement('h2');
    title.textContent = spec.title;
    title.setAttribute('data-test', `obstacle-${spec.id}-title`);
    modal.appendChild(title);

    if (spec.body) {
      const body = document.createElement('p');
      body.textContent = spec.body;
      modal.appendChild(body);
    }

    for (const label of spec.buttons || []) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = label;
      button.setAttribute('data-test', label.toLowerCase().replace(/[^a-z0-9]+/g, '-'));
      button.addEventListener('click', () => overlay.remove());
      modal.appendChild(button);
    }

    overlay.appendChild(modal);
    document.body.appendChild(overlay);
  };

  const fire = (predicate) => {
    for (let i = pending.length - 1; i >= 0; i -= 1) {
      if (predicate(pending[i].trigger)) render(pending.splice(i, 1)[0]);
    }
  };

  document.addEventListener('click', () => {
    clicks += 1;
    fire((trigger) => typeof trigger === 'object' && trigger.after_clicks === clicks);
  });

  fire((trigger) => trigger === 'on_first_load');
})();
