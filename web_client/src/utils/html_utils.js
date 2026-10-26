export class HtmlUtils {
    static isHtmlEmptyOrNull(html) {
        if (!html) return true;
        // Simple strip tags check, matching basic logic.
        // Flutter's HtmlHelper might be more robust, but checking for empty text content is usually sufficient.
        const tmp = document.createElement('div');
        tmp.innerHTML = html;
        const text = tmp.textContent || tmp.innerText || "";
        return text.trim().length === 0;
    }
}
