// hubot runs its own bin through the coffee interpreter, which registers the
// .coffee require extension for us.
module.exports = require('./adapter.coffee');
