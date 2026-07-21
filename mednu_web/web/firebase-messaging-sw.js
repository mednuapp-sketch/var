// Firebase Messaging Service Worker — handles background push notifications
// The Firebase version must match what flutter's firebase_messaging package bundles.
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBh_sDZlUDbE-u-c_4-sWsT1gxvfTYqoco',
  appId: '1:1056867138858:web:2a2aa821fa4ab4f545b253',
  messagingSenderId: '1056867138858',
  projectId: 'mednu-healthcare-app',
  authDomain: 'mednu-healthcare-app.firebaseapp.com',
  storageBucket: 'mednu-healthcare-app.firebasestorage.app',
});

const messaging = firebase.messaging();

// Show notification when app is in the background or closed
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'MedNU';
  const body  = payload.notification?.body  || '';

  return self.registration.showNotification(title, {
    body,
    icon:  '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag:   'mednu-push',
    data:  payload.data || {},
  });
});

// Open/focus the app tab when user clicks a notification
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      return clients.openWindow('/');
    })
  );
});
