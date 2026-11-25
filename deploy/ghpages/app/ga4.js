/* GA4 for the public pages of mynailconnection.com (2026-11-24).
   Loads only on mynailconnection.com and www, so localhost, previews and
   any copy of the site never send visits into the live property.
   The homepage (marketing-v3.html) keeps its own inline loader with the
   same guard, because it also defines mncTrack and the consent defaults. */
(function () {
  var ID = 'G-0859ESXVFR';
  var host = location.hostname;
  if (host !== 'mynailconnection.com' && host !== 'www.mynailconnection.com') return;
  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };
  window.gtag('js', new Date());
  window.gtag('config', ID, { anonymize_ip: true });
  var s = document.createElement('script');
  s.async = true;
  s.src = 'https://www.googletagmanager.com/gtag/js?id=' + ID;
  document.head.appendChild(s);
})();
