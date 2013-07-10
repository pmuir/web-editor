aw.filter('filename', function() {
  return function(file) {
    if(file.links) {
      return file.links[0].text;
    }
  };
});

aw.filter('normalize',function() {
  return function(filename){
    return filename.replace('./','');
  }
});