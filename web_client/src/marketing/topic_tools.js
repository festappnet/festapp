// All layout examples remain visible without JavaScript.
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
  return () => removers.forEach(remove => remove());
}
