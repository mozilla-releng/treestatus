'use strict';

require('expose-loader?jQuery!jquery');
require('expose-loader?Tether!tether');
require('bootstrap');
require('./scss/index.scss');

var url;
var getData = function(name, _default) {
  url = document.body.getAttribute('data-' + name);
  if (url === null) {
    url = _default;
  }
  if (url === undefined) {
    throw Error('You need to set `data-' + name + '`');
  }
  return url;
};

var title = require('./title');
var localstorage = require('./localstorage');
var hawk = require('./hawk');

var release_version = getData('release-version', process.env.RELEASE_VERSION)
var release_channel = getData('release-channel', process.env.RELEASE_CHANNEL);

var TASKCLUSTER_CREDENTIALS_KEY = 'taskcluster_login_credentials';

var init = function() {
    // Start the ELM application
    var app = require('./Main.elm').Main.fullscreen({
      taskclusterCredentials: localstorage.load_item(TASKCLUSTER_CREDENTIALS_KEY),
      taskclusterRootUrl: getData('taskcluster-root-url', process.env.TASKCLUSTER_ROOT_URL),
      treestatusUrl: getData('treestatus-api-url', process.env.TREESTATUS_API_URL),
      version: release_version,
      channel: release_channel,
    });

    // Setup ports
    hawk(app);
    title(app);
};

// Setup logging
var Raven = require('raven-js');
var sentry_dsn = document.body.getAttribute('data-sentry-dsn');
if (sentry_dsn != null) {
    Raven
        .config(
            sentry_dsn,
            {
                debug: true,
                release: release_version,
                environment: release_channel,
                tags: {
                    server_name: 'mozilla/release-services',
                    site: 'releng-frontend'
                }
            })
        .install()
        .context(init);
} else {
    init();
}
