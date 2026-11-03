// 설치(홈 화면 추가)용 서비스워커. 캐시를 안 써서 항상 최신 버전이 열림.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', e => {
  if (e.request.mode === 'navigate') e.respondWith(fetch(e.request).catch(() => new Response('<meta charset="utf-8"><body style="font-family:sans-serif;padding:40px;text-align:center">인터넷 연결을 확인해줘 📶</body>', { headers: { 'Content-Type': 'text/html; charset=utf-8' } })));
});
