// Native inputs keep both tools usable without JavaScript or persisted state.
export function initTopicTools(root = document) {
  const removers = [];
  for (const group of root.querySelectorAll('[data-layout-examples]')) {
    const choices = group.querySelector('[data-layout-choices]');
    const inputs = [...choices.querySelectorAll('input[type="radio"]')];
    const figures = [...group.querySelectorAll('[data-layout-example]')];
    const update = () => {
      const selected = inputs.find(input => input.checked)?.value;
      figures.forEach(figure => { figure.hidden = figure.dataset.layoutExample !== selected; });
    };
    choices.hidden = false;
    choices.addEventListener('change', update);
    update();
    removers.push(() => choices.removeEventListener('change', update));
  }
  for (const checklist of root.querySelectorAll('[data-guide-checklist]')) {
    const inputs = [...checklist.querySelectorAll('input[type="checkbox"]')];
    const progress = checklist.querySelector('[data-guide-progress]');
    const actions = checklist.querySelector('[data-guide-actions]');
    const reset = checklist.querySelector('[data-guide-reset]');
    const print = checklist.querySelector('[data-guide-print]');
    const update = () => {
      const done = inputs.filter(input => input.checked).length;
      progress.textContent = checklist.dataset.progressTemplate.replace('{done}', done).replace('{total}', inputs.length);
      reset.disabled = done === 0;
    };
    const clear = () => { inputs.forEach(input => { input.checked = false; }); update(); };
    const printChecklist = () => (root.defaultView ?? window).print();
    progress.hidden = false;
    actions.hidden = false;
    checklist.addEventListener('change', update);
    reset.addEventListener('click', clear);
    print.addEventListener('click', printChecklist);
    update();
    removers.push(() => {
      checklist.removeEventListener('change', update);
      reset.removeEventListener('click', clear);
      print.removeEventListener('click', printChecklist);
    });
  }
  return () => removers.forEach(remove => remove());
}
