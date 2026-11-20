export function initSeatDemo(copy = {}) {
    const demo = document.querySelector('[data-seat-demo]');
    if (!demo) return;
    const launch = demo.querySelector('[data-seat-start]');
    const status = demo.querySelector('[data-seat-load-status]');
    launch.hidden = false;
    launch.onclick = async () => {
        launch.disabled = true;
        status.textContent = copy.loading ?? 'Načítáme plánek…';
        try {
            const { mountSeatDemo } = await import('./seat_demo.js');
            await mountSeatDemo(demo, copy);
            demo.querySelector('[data-seat-poster]').hidden = true;
            demo.querySelector('[data-seat-controls]').hidden = false;
            demo.querySelector('[data-seat-summary]').hidden = false;
            launch.hidden = true;
            status.textContent = copy.ready ?? 'Plánek je připravený.';
                demo.querySelector('[data-seat-zoom-in]').focus({ preventScroll: true });
        } catch (error) {
            demo.querySelector('[data-seat-map]').hidden = true;
            status.textContent = copy.error ?? 'Plánek se nepodařilo načíst. Zkuste to znovu nebo si přehrajte ukázku níže.';
            console.error('Unable to mount seat demo', error);
        } finally {
            launch.disabled = false;
        }
    };
}
