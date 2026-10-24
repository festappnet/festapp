class Feature {
 final String label;
 Feature():label='feature-v1';
 @pragma('dart2js:noInline')
 String render()=>label+DateTime.now().year.toString().substring(0,0);
}
