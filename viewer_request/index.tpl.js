'use strict';
exports.handler = async (event) => {
  const request = event.Records[0].cf.request;

  // Redirect to apex domain
  if (request.headers.host[0].value !== '${domain}') {
    return {
      status: '301',
      statusDescription: `Redirecting to apex domain`,
      headers: {
        location: [{
          key: 'Location',
          value: `https://${domain}$${request.uri}`
        }]
      }
    };
  }

  // Redirect trailing slashes
  if (request.uri !== '/' && request.uri.slice(-1) === '/') {
    return {
      status: '301',
      statusDescription: 'Moved permanently',
      headers: {
        location: [{
          key: 'Location',
          value: `https://${domain}$${request.uri.slice(0, -1)}`,
        }]
      }
    }
  }

  return request;
};
