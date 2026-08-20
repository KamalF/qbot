// The adapter is loaded by hubot before any .coffee script, so the
// coffee-script compiler must be registered by hand.
require('coffee-script/register');
module.exports = require('./adapter.coffee');
