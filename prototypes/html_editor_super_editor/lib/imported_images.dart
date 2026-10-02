// Local copy of the user-provided image for this standalone, unauthenticated
// experiment. Production uses fetch-http-data and the occasion image upload.
const sampleImageUrl =
    'https://www.festivalslunovrat.cz/wp-content/uploads/2026/09/Rufus-Miller-251x300-optimized.jpeg';

String localImageSource(String source) => source == sampleImageUrl
    ? Uri.base.resolve('imported_images/rufus-miller.jpeg').toString()
    : source;
