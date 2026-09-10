// ============================================
//   MEDNU ADMIN — FCM BACKGROUND SERVICE WORKER
//   Handles push notifications when the admin
//   dashboard tab is backgrounded or closed.
//   Foreground messages (tab open/focused) are
//   handled instead by messaging.onMessage() in
//   js/app.js (initAdminPushNotifications) — the
//   in-tab bell listeners already cover that case.
// ============================================

importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-messaging-compat.js');

// Same public web config as js/firebase-config.js — must match, since this
// registers against the same Firebase project. Not a secret; already shipped
// in the page's own bundle.
firebase.initializeApp({
  apiKey: "AIzaSyBh_sDZlUDbE-u-c_4-sWsT1gxvfTYqoco",
  authDomain: "mednu-healthcare-app.firebaseapp.com",
  projectId: "mednu-healthcare-app",
  storageBucket: "mednu-healthcare-app.firebasestorage.app",
  messagingSenderId: "1056867138858",
  appId: "1:1056867138858:web:2a2aa821fa4ab4f545b253"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification || {};
  self.registration.showNotification(title || 'MedNU Admin', {
    body: body || '',
    icon: '/favicon.ico',
    tag: (payload.data && payload.data.type) || 'mednu-admin-alert',
    data: payload.data || {},
  });
});

// Clicking the OS notification focuses an existing admin tab if one is open,
// otherwise opens a new one — same "get me to the dashboard" behavior either way.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});
