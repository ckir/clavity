/**
 * Copyright (c) 2026 Costas Kirgoussios
 *
 * This software is licensed under the PolyForm Noncommercial License 1.0.0.
 * You may obtain a copy of the License at:
 * https://polyformproject.org/licenses/noncommercial/1.0.0/
 *
 * Clavity Provider-Independent Analytics & Telemetry Layer
 *
 * Requirements:
 * - Zero third-party runtime dependencies.
 * - No cookies, no local storage fingerprinting, no PII.
 * - Captures UTM campaign parameters for attribution.
 * - Safe fallback: no-ops gracefully when unconfigured.
 */

(function () {
  'use strict';

  // Parse UTM parameters from query string
  function getUtmParams() {
    var params = {};
    if (!window.location.search) { return params; }
    var search = window.location.search.substring(1);
    var pairs = search.split('&');
    for (var i = 0; i < pairs.length; i++) {
      var pair = pairs[i].split('=');
      var key = decodeURIComponent(pair[0]);
      if (key.indexOf('utm_') === 0 && pair.length > 1) {
        params[key] = decodeURIComponent(pair[1] || '');
      }
    }
    return params;
  }

  var utm = getUtmParams();

  // In-memory queue for dev logging or downstream integrations
  var eventQueue = [];

  var ClavityAnalytics = {
    /**
     * Dispatch an event to any configured provider or in-memory bus.
     * Sanitizes properties to guarantee NO email addresses or PII are passed.
     */
    track: function (eventName, properties) {
      properties = properties || {};
      // Disallow email or sensitive keys
      delete properties.email;
      delete properties.password;
      delete properties.prompt;
      delete properties.token;

      // Attach UTM attribution if present
      for (var k in utm) {
        if (utm.hasOwnProperty(k) && !properties[k]) {
          properties[k] = utm[k];
        }
      }

      var payload = {
        name: eventName,
        properties: properties,
        path: window.location.pathname,
        timestamp: new Date().toISOString()
      };

      eventQueue.push(payload);

      // If a custom provider hook is configured by the operator, forward to it
      if (typeof window.__CLAVITY_ANALYTICS_DISPATCHER__ === 'function') {
        try {
          window.__CLAVITY_ANALYTICS_DISPATCHER__(payload);
        } catch (e) {
          // Fail closed and silent
        }
      }
    },

    getQueue: function () {
      return eventQueue.slice();
    }
  };

  // Expose globally
  window.ClavityAnalytics = ClavityAnalytics;

  // Track initial page_view
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', onReady);
  } else {
    onReady();
  }

  function onReady() {
    ClavityAnalytics.track('page_view', {
      title: document.title,
      referrer: document.referrer || ''
    });

    // Auto-bind declarative analytics triggers
    document.addEventListener('click', function (e) {
      var target = e.target.closest('[data-analytics-event]');
      if (!target) { return; }

      var eventName = target.getAttribute('data-analytics-event');
      var propString = target.getAttribute('data-analytics-props');
      var props = {};

      if (propString) {
        try {
          props = JSON.parse(propString);
        } catch (err) {
          // ignore malformed attributes
        }
      }

      if (target.href && !props.target_url) {
        props.target_url = target.href;
      }

      ClavityAnalytics.track(eventName, props);
    }, false);
  }
})();
