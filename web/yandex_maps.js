(function () {
  const entries = new Map();
  const defaultCenter = [34.359757, 61.789114]; // [lon, lat] for v3
  const defaultZoom = 14;

  let renderingApi = null;
  let renderingLocale = null;
  let renderingPromise = null;
  let clusterModule = null;
  const searchConfigPromises = new Map();
  let searchJsonpSequence = 0;
  const cameraEmitIntervalMs = 100;
  const promoSelectors = [
    '[class*="-gotoymaps"]',
    '[class*="-gototech"]',
  ];

  function normalizeLocale(locale) {
    return locale === 'en_RU' ? 'en_RU' : 'ru_RU';
  }

  function serviceApiKey() {
    const script = document.querySelector('script[src*="api-maps.yandex.ru/2.1/"]');
    if (!script || !script.src) return null;
    return new URL(script.src).searchParams.get('apikey');
  }

  function serviceSearchLocale(locale) {
    return locale === 'ru_RU' ? 'ru_RU' : 'en_US';
  }

  function loadSearchServiceConfig(locale, apiKey, forceRefresh = false) {
    const configKey = `${locale}:${apiKey}`;
    if (forceRefresh) searchConfigPromises.delete(configKey);
    const existing = searchConfigPromises.get(configKey);
    if (existing) return existing;

    const params = new URLSearchParams({ lang: locale, apikey: apiKey });
    const promise = fetch(
      `https://api-maps.yandex.ru/v3/config?${params.toString()}`,
      { cache: 'no-store' }
    )
      .then((response) => {
        if (!response.ok) {
          throw new Error(`search_config_http_${response.status}`);
        }
        return response.json();
      })
      .then((config) => {
        if (!config || typeof config.token !== 'string' || !config.token) {
          throw new Error('search_config_missing_token');
        }
        return config;
      })
      .catch((error) => {
        searchConfigPromises.delete(configKey);
        throw error;
      });
    searchConfigPromises.set(configKey, promise);
    return promise;
  }

  async function searchViaServices(
    text,
    locale,
    apiKey,
    center,
    span,
    retry = true
  ) {
    const config = await loadSearchServiceConfig(locale, apiKey, !retry);
    const callbackName = `jsonp_ymaps3_search_parktrack_${++searchJsonpSequence}`;
    const params = new URLSearchParams({
      lang: locale,
      token: config.token,
      apikey: apiKey,
      text,
      results: '10',
      callback: callbackName,
      origin: 'jsapi3Geocoder',
      geocoder_sco: 'longlat',
    });
    if (center && span) {
      params.set('ll', `${center[0]},${center[1]}`);
      params.set('spn', `${span[0]},${span[1]}`);
      params.set('rspn', '1');
    }

    try {
      return await new Promise((resolve, reject) => {
        const script = document.createElement('script');
        const timeout = setTimeout(() => {
          cleanup();
          reject(new Error('services_search_timeout'));
        }, 4000);

        function cleanup() {
          clearTimeout(timeout);
          try { delete window[callbackName]; } catch (_) {
            window[callbackName] = undefined;
          }
          script.remove();
        }

        window[callbackName] = (payload) => {
          cleanup();
          if (
            payload &&
            payload.status === 'success' &&
            payload.data &&
            Array.isArray(payload.data.features)
          ) {
            resolve(payload.data.features);
          } else {
            reject(new Error('services_search_failed'));
          }
        };
        script.onerror = () => {
          cleanup();
          reject(new Error('services_search_load_failed'));
        };
        script.src =
          `https://api-maps.yandex.ru/services/search/?${params.toString()}`;
        document.head.appendChild(script);
      });
    } catch (error) {
      if (retry) {
        return searchViaServices(text, locale, apiKey, center, span, false);
      }
      throw error;
    }
  }

  function loadRenderingApi(locale) {
    const requestedLocale = normalizeLocale(locale);
    if (renderingApi) return Promise.resolve(renderingApi);
    if (renderingPromise) return renderingPromise;

    const apiKey = serviceApiKey();
    if (!apiKey) return Promise.reject(new Error('missing_api_key'));

    renderingLocale = requestedLocale;
    renderingPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.id = 'yandex-maps-rendering';
      script.src = `https://api-maps.yandex.ru/v3/?apikey=${encodeURIComponent(apiKey)}&lang=${requestedLocale}`;
      script.onload = async () => {
        try {
          if (!window.ymaps3) throw new Error('rendering_api_unavailable');
          await window.ymaps3.ready;
          renderingApi = window.ymaps3;
          try {
            clusterModule = await renderingApi.import('@yandex/ymaps3-clusterer@0.0.1');
          } catch (e) {
            console.warn('Failed to load clusterer:', e);
          }
          resolve(renderingApi);
        } catch (error) {
          renderingPromise = null;
          reject(error);
        }
      };
      script.onerror = () => {
        renderingPromise = null;
        reject(new Error('rendering_api_load_failed'));
      };
      document.head.appendChild(script);
    });
    return renderingPromise;
  }

  function destroyMapInstance(entry) {
    if (entry.cameraTimer != null) {
      clearTimeout(entry.cameraTimer);
      entry.cameraTimer = null;
    }
    if (entry.promoFrame != null) {
      cancelAnimationFrame(entry.promoFrame);
      entry.promoFrame = null;
    }
    if (entry.map) {
      try { entry.map.destroy(); } catch (e) {}
    }
    entry.map = null;
    entry.schemeLayer = null;
    entry.zoneGeometryObjects = [];
    entry.zoneMarkerObjects = [];
    entry.zoneFeatures = new Map();
    entry.routeObjects = [];
    entry.positionObjects = [];
    entry.zoneGeometrySignature = null;
    entry.zoneStyleSignature = null;
    entry.zoneMarkerSignature = null;
    entry.routeSignature = null;
    entry.positionSignature = null;
    entry.lastCameraKey = null;
  }

  function emitCamera(entry) {
    if (!entry.map || !entry.map.center || !entry.map.bounds) return false;

    const center = entry.map.center;
    const bounds = entry.map.bounds;
    if (!bounds[0] || !bounds[1]) return false;
    const zoom = entry.map.zoom;
    const azimuth = Number(entry.map.azimuth || 0);
    const cameraKey = [
      center[0],
      center[1],
      zoom,
      bounds[0][0],
      bounds[0][1],
      bounds[1][0],
      bounds[1][1],
      azimuth,
    ]
      .map((value) => Number(value).toFixed(7))
      .join('|');

    entry.center = [...center];
    entry.zoom = zoom;
    if (cameraKey === entry.lastCameraKey) return true;
    entry.lastCameraKey = cameraKey;
    entry.onCamera(JSON.stringify({
      latitude: center[1],
      longitude: center[0],
      zoom,
      west: bounds[0][0],
      south: bounds[0][1],
      east: bounds[1][0],
      north: bounds[1][1],
      azimuth,
    }));
    return true;
  }

  function scheduleCameraEmit(entry) {
    if (entry.destroyed || entry.cameraTimer != null) return;
    entry.cameraTimer = setTimeout(() => {
      entry.cameraTimer = null;
      emitCamera(entry);
    }, cameraEmitIntervalMs);
  }

  function hidePromoElements(root) {
    if (!root || typeof root.querySelectorAll !== 'function') return;
    for (const selector of promoSelectors) {
      if (typeof root.matches === 'function' && root.matches(selector)) {
        root.style.display = 'none';
        root.style.visibility = 'hidden';
      }
      root.querySelectorAll(selector).forEach((element) => {
        element.style.display = 'none';
        element.style.visibility = 'hidden';
      });
    }
    root.querySelectorAll('*').forEach((element) => {
      if (element.shadowRoot) hidePromoElements(element.shadowRoot);
    });
  }

  function schedulePromoScan(entry, roots) {
    if (entry.destroyed) return;
    for (const root of roots) entry.pendingPromoRoots.add(root);
    if (entry.promoFrame != null) return;
    entry.promoFrame = requestAnimationFrame(() => {
      entry.promoFrame = null;
      const pendingRoots = [...entry.pendingPromoRoots];
      entry.pendingPromoRoots.clear();
      for (const root of pendingRoots) hidePromoElements(root);
    });
  }

  function addObject(entry, object, group) {
    if (!entry.map) return null;
    entry.map.addChild(object);
    entry[group].push(object);
    return object;
  }

  function clearObjectGroup(entry, group) {
    for (const object of entry[group]) {
      try { entry.map.removeChild(object); } catch (_) {}
    }
    entry[group] = [];
  }

  function parkingLinePoints(points) {
    if (points.length < 4) return points;

    const midpoint = (a, b) => [
      (a[0] + b[0]) / 2,
      (a[1] + b[1]) / 2,
    ];
    const distanceSquared = (a, b) =>
      Math.pow(a[0] - b[0], 2) + Math.pow(a[1] - b[1], 2);

    if (
      distanceSquared(points[0], points[1]) <=
      distanceSquared(points[1], points[2])
    ) {
      return [midpoint(points[0], points[1]), midpoint(points[2], points[3])];
    }
    return [midpoint(points[1], points[2]), midpoint(points[3], points[0])];
  }

  function parkingMarkerElement(zone, onTap) {
    const el = document.createElement('div');
    el.className = 'parktrack-marker';
    const zIndex = zone.active ? 2300 : zone.candidate ? 2200 : 2100;
    el.style.cssText = `position:absolute;left:0;top:0;transform:translate(-50%,-50%);min-width:20px;height:20px;box-sizing:border-box;border:0;border-radius:9999px;padding:2px 6px;background:${zone.stroke};display:flex;align-items:center;justify-content:center;color:${zone.markerTextColor};font:600 12px/16px Roboto,Arial,sans-serif;white-space:nowrap;cursor:pointer;box-shadow:0 1px 3px rgba(0,0,0,.1),0 1px 2px rgba(0,0,0,.1);opacity:${zone.markerOpacity ?? 1};z-index:${zIndex}`;
    el.textContent = zone.label == null ? '' : String(zone.label);
    el.onclick = (e) => { e.stopPropagation(); onTap(); };
    return el;
  }

  function ensureUserLocationStyles() {
    if (document.getElementById('parktrack-user-location-styles')) return;
    const style = document.createElement('style');
    style.id = 'parktrack-user-location-styles';
    style.textContent = `
      .parktrack-user-location {
        --heading: -90deg;
        --marker-color: #ff3b30;
        --arrow-color: #d83329;
        position: absolute;
        left: -32px;
        top: -32px;
        width: 64px;
        height: 64px;
        box-sizing: border-box;
        pointer-events: none;
      }
      .parktrack-user-location__direction {
        position: absolute;
        z-index: 1;
        top: 50%;
        left: 50%;
        width: 30px;
        height: 55px;
        transform: translate(0, -50%) rotate(var(--heading));
        transform-origin: 0 50%;
        background: var(--arrow-color);
        clip-path: polygon(0 18%, 100% 50%, 0 82%, 0 50%);
        filter: drop-shadow(0 2px 2px rgb(0 0 0 / 16%));
      }
      .parktrack-user-location__point {
        position: absolute;
        z-index: 2;
        top: 50%;
        left: 50%;
        width: 36px;
        height: 36px;
        transform: translate(-50%, -50%);
        border: 3px solid rgb(255 255 255 / 92%);
        border-radius: 50%;
        background: #fff;
        box-shadow:
          0 2px 7px rgb(0 0 0 / 25%),
          0 0 0 1px rgb(0 0 0 / 3%);
        box-sizing: border-box;
      }
      .parktrack-user-location__point::after {
        content: "";
        position: absolute;
        inset: 4.5px;
        border-radius: 50%;
        background: var(--marker-color);
        box-shadow:
          inset 0 1px 1px rgb(255 255 255 / 32%),
          0 1px 2px rgb(0 0 0 / 18%);
      }
    `;
    document.head.appendChild(style);
  }

  function normalizedDeviceHeading(event) {
    if (Number.isFinite(Number(event.webkitCompassHeading))) {
      return (Number(event.webkitCompassHeading) + 360) % 360;
    }
    if (!event.absolute || !Number.isFinite(Number(event.alpha))) return null;
    const screenAngle =
      (screen.orientation && Number(screen.orientation.angle)) ||
      Number(window.orientation) ||
      0;
    return (360 - Number(event.alpha) + screenAngle + 360) % 360;
  }

  function attachDeviceHeading(entry) {
    if (entry.orientationHandler || !window.DeviceOrientationEvent) return;
    entry.orientationHandler = (event) => {
      const heading = normalizedDeviceHeading(event);
      if (
        heading == null ||
        Math.abs(heading - (entry.deviceHeading ?? -999)) < 0.5
      ) {
        return;
      }
      entry.deviceHeading = heading;
      entry.positionSignature = null;
      if (entry.latestState) renderPositions(entry, entry.latestState);
    };
    window.addEventListener(
      'deviceorientationabsolute',
      entry.orientationHandler,
      true
    );
    window.addEventListener('deviceorientation', entry.orientationHandler, true);
  }

  async function requestDeviceHeading(entry) {
    const orientation = window.DeviceOrientationEvent;
    if (!orientation) return;
    if (typeof orientation.requestPermission === 'function') {
      try {
        if (await orientation.requestPermission() !== 'granted') return;
      } catch (error) {
        console.warn('Device orientation permission failed:', error);
        return;
      }
    }
    attachDeviceHeading(entry);
  }

  function clusterSize(zoneCount) {
    return Math.min(28 + Math.floor(zoneCount / 4) * 4, 44);
  }

  function clusterMarkerElement(features, onTap) {
    const zones = features.map(f => f.properties.zone);
    const freeCount = zones.reduce(
      (sum, zone) =>
        sum + (zone.isActive ? Math.max(0, Number(zone.freeCount ?? 0)) : 0),
      0
    );
    const el = document.createElement('div');
    el.className = 'parktrack-cluster';
    const opacity = Math.max(
      ...zones.map(zone => Number(zone.markerOpacity ?? 1))
    );
    const color = freeCount === 0
      ? zones[0].clusterFull
      : freeCount <= 2
        ? zones[0].clusterOne
        : zones[0].clusterFree;
    const size = clusterSize(zones.length);
    const fontSize = size >= 38 ? 13 : 11;
    el.style.cssText = `position:absolute;left:0;top:0;transform:translate(-50%,-50%);width:${size}px;height:${size}px;box-sizing:border-box;border:0;border-radius:9999px;background:${color};display:flex;align-items:center;justify-content:center;text-align:center;color:${zones[0].markerTextColor};font:600 ${fontSize}px/1 Roboto,Arial,sans-serif;cursor:pointer;box-shadow:0 4px 6px -1px rgba(0,0,0,.1),0 2px 4px -2px rgba(0,0,0,.1),0 0 0 2px rgba(255,255,255,.7);opacity:${opacity};z-index:2100`;
    el.textContent = String(freeCount);
    el.onclick = (e) => { e.stopPropagation(); onTap(); };
    return el;
  }

  function worldPixel(coordinates, zoom) {
    const longitude = coordinates[0];
    const latitude = Math.max(-85.05112878, Math.min(85.05112878, coordinates[1]));
    const scale = 256 * Math.pow(2, zoom);
    const sinLatitude = Math.sin(latitude * Math.PI / 180);
    return [
      ((longitude + 180) / 360) * scale,
      (0.5 -
        Math.log((1 + sinLatitude) / (1 - sinLatitude)) /
          (4 * Math.PI)) * scale,
    ];
  }

  function clusterComponentCount(features, zoom, radius = 22) {
    const parents = features.map((_, index) => index);
    const root = (index) => {
      while (parents[index] !== index) {
        parents[index] = parents[parents[index]];
        index = parents[index];
      }
      return index;
    };
    const pixels = features.map(feature =>
      worldPixel(feature.geometry.coordinates, zoom)
    );
    for (let left = 0; left < pixels.length; left++) {
      for (let right = left + 1; right < pixels.length; right++) {
        const dx = pixels[left][0] - pixels[right][0];
        const dy = pixels[left][1] - pixels[right][1];
        if (Math.hypot(dx, dy) <= radius) {
          const leftRoot = root(left);
          const rightRoot = root(right);
          if (leftRoot !== rightRoot) parents[rightRoot] = leftRoot;
        }
      }
    }
    return new Set(features.map((_, index) => root(index))).size;
  }

  function clusterExpansionZoom(features, currentZoom) {
    let zoom = Math.ceil((currentZoom + 0.5) * 2) / 2;
    while (zoom < 21 && clusterComponentCount(features, zoom, 64) < 2) {
      zoom += 0.5;
    }
    return Math.min(21, Math.max(currentZoom + 0.5, zoom));
  }

  function clusterCenter(features) {
    const points = features.map(feature => feature.geometry.coordinates);
    return [
      points.reduce((sum, point) => sum + point[0], 0) / points.length,
      points.reduce((sum, point) => sum + point[1], 0) / points.length,
    ];
  }

  function zoneFeatureStyle(zone) {
    const isLine = zone.type === 'line' || zone.points.length < 3;
    return {
      stroke: [{
        color: zone.stroke,
        width: zone.active ? (isLine ? 8 : 3) : (isLine ? 6 : 1),
      }],
      fill: isLine ? undefined : zone.fill,
    };
  }

  function renderPositions(entry, state) {
    if (!entry.map || !renderingApi) return;
    const { YMapMarker } = renderingApi;
    const effectiveUserHeading = entry.deviceHeading ?? state.user?.[2] ?? 0;
    const positionSignature = JSON.stringify([
      state.navigation || null,
      state.user
        ? [state.user[0], state.user[1], effectiveUserHeading]
        : null,
      state.destination || null,
    ]);
    if (positionSignature === entry.positionSignature) return;
    entry.positionSignature = positionSignature;
    clearObjectGroup(entry, 'positionObjects');

    if (state.navigation) {
      const angle = state.navigation[2] || 0;
      const el = document.createElement('div');
      el.style.cssText = `position:absolute;left:-14px;top:-14px;width:28px;height:28px;z-index:2400`;
      el.innerHTML = `<svg viewBox="0 0 80 80" width="28" height="28" style="filter:drop-shadow(0 1px 2px rgba(0,0,0,0.45));transform:rotate(${angle}deg)"><path d="M40 4 L62.4 57.6 L40 44.8 L17.6 57.6 Z" fill="#007aff" stroke="#fff" stroke-width="3" stroke-linejoin="round"/></svg>`;
      addObject(entry, new YMapMarker({
        coordinates: [state.navigation[1], state.navigation[0]]
      }, el), 'positionObjects');
    }
    if (state.user) {
      ensureUserLocationStyles();
      const el = document.createElement('div');
      el.className = 'parktrack-user-location';
      el.setAttribute('aria-label', 'Your location');
      el.style.setProperty('--heading', `${effectiveUserHeading - 90}deg`);
      el.innerHTML =
        '<span class="parktrack-user-location__direction"></span>' +
        '<span class="parktrack-user-location__point"></span>';
      addObject(entry, new YMapMarker({
        coordinates: [state.user[1], state.user[0]]
      }, el), 'positionObjects');
    }
    if (state.destination) {
      const el = document.createElement('div');
      el.style.cssText = 'position:absolute;left:-16px;top:-40px;width:32px;height:40px;z-index:2300';
      el.innerHTML = '<svg viewBox="0 0 32 40" width="32" height="40" style="filter:drop-shadow(0 2px 2px rgba(0,0,0,.35))"><path d="M16 39C13 32 4 24 4 14A12 12 0 0 1 28 14C28 24 19 32 16 39Z" fill="#2e7d32" stroke="#fff" stroke-width="2"/><circle cx="16" cy="14" r="4" fill="#fff"/></svg>';
      addObject(entry, new YMapMarker({
        coordinates: [state.destination[1], state.destination[0]]
      }, el), 'positionObjects');
    }
  }

  function render(entry, state) {
    entry.latestState = state;
    if (!entry.map || !renderingApi) return;

    const theme = state.theme === 'dark' ? 'dark' : 'light';
    if (theme !== entry.theme) {
      entry.theme = theme;
      if (entry.schemeLayer) entry.schemeLayer.update({ theme });
    }

    const zones = state.zones || [];
    const { YMapFeature, YMapMarker } = renderingApi;

    const zoneGeometrySignature = JSON.stringify(
      zones.map(zone => [zone.id, zone.type, zone.points])
    );
    if (zoneGeometrySignature !== entry.zoneGeometrySignature) {
      entry.zoneGeometrySignature = zoneGeometrySignature;
      clearObjectGroup(entry, 'zoneGeometryObjects');
      entry.zoneFeatures.clear();
      for (const zone of zones) {
        if (!zone.points || zone.points.length < 2) continue;
        const isLine = zone.type === 'line' || zone.points.length < 3;
        const geometryPoints = isLine
          ? parkingLinePoints(zone.points)
          : zone.points;
        const coords = geometryPoints.map(p => [p[1], p[0]]);
        const feature = new YMapFeature({
          geometry: isLine
            ? { type: 'LineString', coordinates: coords }
            : { type: 'Polygon', coordinates: [coords] },
          style: zoneFeatureStyle(zone),
          onClick: () => {
            entry.zoneTapAt = performance.now();
            entry.onZoneTap(zone.id);
          }
        });
        entry.zoneFeatures.set(zone.id, feature);
        addObject(entry, feature, 'zoneGeometryObjects');
      }
    }

    const zoneStyleSignature = JSON.stringify(
      zones.map(zone => [zone.id, zone.fill, zone.stroke, zone.active])
    );
    if (zoneStyleSignature !== entry.zoneStyleSignature) {
      entry.zoneStyleSignature = zoneStyleSignature;
      for (const zone of zones) {
        entry.zoneFeatures.get(zone.id)?.update({
          style: zoneFeatureStyle(zone)
        });
      }
    }

    const zoneMarkerSignature = JSON.stringify(
      zones.map(zone => [
        zone.id,
        zone.center,
        zone.freeCount,
        zone.isActive,
        zone.markerOpacity,
        zone.stroke,
        zone.markerTextColor,
        zone.active,
        zone.candidate,
      ])
    );
    if (zoneMarkerSignature !== entry.zoneMarkerSignature) {
      entry.zoneMarkerSignature = zoneMarkerSignature;
      clearObjectGroup(entry, 'zoneMarkerObjects');
      if (clusterModule && zones.length >= 2) {
        const features = zones.map(zone => ({
          type: 'Feature', id: String(zone.id),
          geometry: {
            type: 'Point',
            coordinates: [zone.center[1], zone.center[0]],
          },
          properties: { zone }
        }));
        addObject(entry, new clusterModule.YMapClusterer({
          method: clusterModule.clusterByGrid({ gridSize: 64 }),
          features,
          marker: (feature) => new YMapMarker(
            { coordinates: feature.geometry.coordinates },
            parkingMarkerElement(
              feature.properties.zone,
              () => {
                entry.zoneTapAt = performance.now();
                entry.onZoneTap(feature.properties.zone.id);
              }
            )
          ),
          cluster: (_, clusterFeatures) => {
            const center = clusterCenter(clusterFeatures);
            return new YMapMarker(
              { coordinates: center },
              clusterMarkerElement(
                clusterFeatures,
                () => entry.map.setLocation({
                  center,
                  zoom: clusterExpansionZoom(clusterFeatures, entry.map.zoom),
                  duration: 300,
                })
              )
            );
          }
        }), 'zoneMarkerObjects');
      } else {
        for (const zone of zones) {
          addObject(entry, new YMapMarker(
            { coordinates: [zone.center[1], zone.center[0]] },
            parkingMarkerElement(zone, () => {
              entry.zoneTapAt = performance.now();
              entry.onZoneTap(zone.id);
            })
          ), 'zoneMarkerObjects');
        }
      }
    }

    const routeSignature = JSON.stringify(state.route || null);
    if (routeSignature !== entry.routeSignature) {
      entry.routeSignature = routeSignature;
      clearObjectGroup(entry, 'routeObjects');
    }
    if (state.route && entry.routeObjects.length === 0) {
      addObject(entry, new YMapFeature({
        geometry: { type: 'LineString', coordinates: state.route.map(p => [p[1], p[0]]) },
        style: { stroke: [{ color: '#2196f3', width: 6 }] }
      }), 'routeObjects');
    }

    renderPositions(entry, state);
  }

  async function initializeMap(entry) {
    if (entry.destroyed || entry.initializing) return;
    entry.initializing = true;
    try {
      const api = await loadRenderingApi(entry.locale);
      if (entry.destroyed) return;
      entry.map = new api.YMap(entry.element, {
        location: { center: entry.center, zoom: entry.zoom },
        theme: entry.theme,
        behaviors: ['drag', 'scrollZoom', 'pinchZoom', 'dblClick']
      });
      entry.schemeLayer = new api.YMapDefaultSchemeLayer({ theme: entry.theme });
      entry.map.addChild(entry.schemeLayer);
      entry.map.addChild(new api.YMapDefaultFeaturesLayer());
      entry.map.addChild(new api.YMapListener({
        onUpdate: () => scheduleCameraEmit(entry),
        onClick: () => {
          if (performance.now() - (entry.zoneTapAt || 0) > 80) {
            entry.onMapTap();
          }
        },
      }));
      if (entry.latestState) render(entry, entry.latestState);

      // Ensure initial camera is emitted once map is ready and has bounds
      let attempts = 0;
      const checkBounds = () => {
        if (entry.destroyed) return;
        if (emitCamera(entry)) return;
        if (attempts++ < 20) setTimeout(checkBounds, 150);
      };
      checkBounds();
    } catch (e) {
      console.error('Map init fail:', e);
      entry.onError('map_load');
    } finally {
      entry.initializing = false;
    }
  }

  window.parkTrackYandexMaps = {
    create(element, locale, theme, onCamera, onZoneTap, onMapTap, onError) {
      const elementId = element.id;
      const entry = {
        element, locale: normalizeLocale(locale), theme,
        onCamera, onZoneTap, onMapTap, onError,
        map: null,
        zoneGeometryObjects: [],
        zoneMarkerObjects: [],
        zoneFeatures: new Map(),
        routeObjects: [],
        positionObjects: [],
        center: [...defaultCenter],
        zoom: defaultZoom,
        pendingPromoRoots: new Set(),
        cameraTimer: null,
        promoFrame: null,
        zoneTapAt: 0,
        latestStateJson: null,
        destroyed: false,
      };
      entries.set(elementId, entry);

      const observer = new MutationObserver((mutations) => {
        const addedRoots = [];
        for (const mutation of mutations) {
          for (const node of mutation.addedNodes) {
            if (node.nodeType === Node.ELEMENT_NODE) addedRoots.push(node);
          }
        }
        if (addedRoots.length) schedulePromoScan(entry, addedRoots);
      });
      observer.observe(element, { childList: true, subtree: true });
      entry.observer = observer;
      schedulePromoScan(entry, [element]);

      initializeMap(entry);
      attachDeviceHeading(entry);
    },
    update(id, state) {
      const entry = entries.get(id);
      if (!entry || state === entry.latestStateJson) return;
      entry.latestStateJson = state;
      render(entry, JSON.parse(state));
    },
    updatePosition(id, state) {
      const entry = entries.get(id);
      if (!entry) return;
      const positions = JSON.parse(state);
      entry.latestState = Object.assign(entry.latestState || {}, positions);
      renderPositions(entry, entry.latestState);
    },
    move(id, lat, lon, zoom) {
      const entry = entries.get(id);
      if (entry && entry.map) entry.map.setLocation({ center: [lon, lat], zoom, duration: 300 });
    },
    setZoom(id, z) {
      const entry = entries.get(id);
      if (entry && entry.map) entry.map.setLocation({ zoom: z, duration: 200 });
    },
    resetNorth(id) {
      const entry = entries.get(id);
      if (entry && entry.map) {
        entry.map.setLocation({ azimuth: 0, tilt: 0, duration: 400 });
      }
    },
    requestHeading(id) {
      const entry = entries.get(id);
      if (entry) requestDeviceHeading(entry);
    },
    fitBounds(id, south, west, north, east, top, right, bottom, left) {
      const entry = entries.get(id);
      if (entry && entry.map) {
        entry.map.update({
          margin: [top || 0, right || 0, bottom || 0, left || 0]
        });
        entry.map.setLocation({
          bounds: [[west, south], [east, north]],
          duration: 600
        });
      }
    },
    focus(id, lat, lon, zoom, top, right, bottom, left) {
      const entry = entries.get(id);
      if (entry && entry.map) {
        entry.map.update({
          margin: [top || 0, right || 0, bottom || 0, left || 0]
        });
        entry.map.setLocation({
          center: [lon, lat],
          zoom,
          duration: 300
        });
      }
    },
    retry(id) {
      const entry = entries.get(id);
      if (!entry) return;
      entry.center = entry.map ? [...entry.map.center] : [...entry.center];
      entry.zoom = entry.map ? entry.map.zoom : entry.zoom;
      destroyMapInstance(entry);
      entry.destroyed = false;
      initializeMap(entry);
    },
    destroy(id) {
      const entry = entries.get(id);
      if (entry) {
        entry.destroyed = true;
        if (entry.orientationHandler) {
          window.removeEventListener(
            'deviceorientationabsolute',
            entry.orientationHandler,
            true
          );
          window.removeEventListener(
            'deviceorientation',
            entry.orientationHandler,
            true
          );
        }
        if (entry.observer) entry.observer.disconnect();
        destroyMapInstance(entry);
        entries.delete(id);
      }
    },
    async route(fLat, fLon, tLat, tLon) {
      try {
        const api = await loadRenderingApi(renderingLocale || 'ru_RU');
        if (typeof api.route !== 'function') {
          throw new Error('ymaps3_route_unavailable');
        }
        const routerApiKey = serviceApiKey();
        if (!routerApiKey) throw new Error('missing_router_api_key');
        api.getDefaultConfig().setApikeys({ router: routerApiKey });
        const responses = await api.route({
          points: [[fLon, fLat], [tLon, tLat]],
          type: 'driving',
        });
        const response = Array.isArray(responses) ? responses[0] : null;
        const feature =
          response && typeof response.toRoute === 'function'
            ? response.toRoute()
            : null;
        const coordinates =
          feature &&
          feature.geometry &&
          Array.isArray(feature.geometry.coordinates)
            ? feature.geometry.coordinates
            : [];
        const points = coordinates
          .filter(coordinate =>
            Array.isArray(coordinate) &&
            coordinate.length >= 2 &&
            Number.isFinite(Number(coordinate[0])) &&
            Number.isFinite(Number(coordinate[1]))
          )
          .map(coordinate => [Number(coordinate[1]), Number(coordinate[0])]);
        if (points.length >= 2) {
          const properties = feature.properties || {};
          return JSON.stringify({
            points,
            duration: Number(properties.duration) || 0,
            distance: Number(properties.length) || 0,
          });
        }
        throw new Error('ymaps3_route_empty');
      } catch (error) {
        console.warn('Yandex Maps v3 route failed, using v2.1 fallback:', error);
      }

      return new Promise((resolve) => {
        if (!window.ymaps) return resolve(JSON.stringify({ points: [], duration: 0, distance: 0 }));
        window.ymaps.ready(() => {
          window.ymaps.route([[fLat, fLon], [tLat, tLon]], { routingMode: 'auto' })
            .then(r => {
              const points = [];
              r.getPaths().each(p => p.geometry.getCoordinates().forEach(c => {
                if (!points.length || points[points.length-1][0] !== c[0] || points[points.length-1][1] !== c[1]) points.push(c);
              }));
              resolve(JSON.stringify({ points, duration: r.getTime(), distance: r.getLength() }));
            }, () => resolve(JSON.stringify({ points: [], duration: 0, distance: 0 })));
        });
      });
    },
    async suggest(text, s, w, n, e) {
      const query = String(text || '').trim();
      if (!query) return '[]';

      const hasBounds =
        Number.isFinite(s) &&
        Number.isFinite(w) &&
        Number.isFinite(n) &&
        Number.isFinite(e) &&
        n > s &&
        e > w;
      const locale = normalizeLocale(renderingLocale || 'ru_RU');
      const mapsApiKey = serviceApiKey();

      // Search twice: strictly inside the current viewport for local priority,
      // then without bounds so a city or organization elsewhere is still found.
      try {
        if (!mapsApiKey) throw new Error('missing_api_key');
        const searchLocale = serviceSearchLocale(locale);
        const localCenter = hasBounds
          ? [(w + e) / 2, (s + n) / 2]
          : null;
        const localSpan = hasBounds
          ? [
              Math.min(Math.max(e - w, 0.001), 3),
              Math.min(Math.max(n - s, 0.001), 2),
            ]
          : null;
        const localRequest = hasBounds
          ? searchViaServices(
              query,
              searchLocale,
              mapsApiKey,
              localCenter,
              localSpan
            ).catch((error) => {
              console.warn('Local Yandex services search failed:', error);
              return [];
            })
          : Promise.resolve([]);
        const globalRequest = searchViaServices(
          query,
          searchLocale,
          mapsApiKey,
          null,
          null
        ).catch((error) => {
          console.warn('Global Yandex services search failed:', error);
          return [];
        });
        const [localFeatures, globalFeatures] = await Promise.all([
          localRequest,
          globalRequest,
        ]);

        const seen = new Set();
        const items = [];
        for (const feature of [
          ...(Array.isArray(localFeatures) ? localFeatures : []),
          ...(Array.isArray(globalFeatures) ? globalFeatures : []),
        ]) {
          const properties = feature && feature.properties;
          const company = properties && properties.CompanyMetaData;
          const geometry =
            feature &&
            (feature.geometry ||
              (Array.isArray(feature.geometries) && feature.geometries[0]));
          const coordinates =
            geometry && geometry.type === 'Point' && geometry.coordinates;
          if (!properties || !Array.isArray(coordinates)) continue;

          const longitude = Number(coordinates[0]);
          const latitude = Number(coordinates[1]);
          if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) continue;

          const title =
            (company && company.name) ||
            properties.name ||
            properties.description ||
            query;
          const subtitle =
            (company && company.address) ||
            properties.description ||
            null;
          const dedupeKey = [
            (company && company.id) || properties.id || title.toLocaleLowerCase(),
            latitude.toFixed(6),
            longitude.toFixed(6),
          ].join('|');
          if (seen.has(dedupeKey)) continue;
          seen.add(dedupeKey);
          items.push({
            title,
            subtitle: subtitle && subtitle !== title ? subtitle : null,
            searchText: [title, subtitle].filter(Boolean).join(', '),
            latitude,
            longitude,
          });
        }
        if (items.length) return JSON.stringify(items);
      } catch (error) {
        console.warn('Yandex services search failed, using geocoder fallback:', error);
      }

      // Address-only fallback for cases where the JS API search service is
      // temporarily unavailable.
      if (mapsApiKey) {
        try {
          const params = new URLSearchParams({
            apikey: mapsApiKey,
            geocode: query,
            format: 'json',
            lang: locale,
            results: '20',
          });
          if (hasBounds) {
            params.set('bbox', `${w},${s}~${e},${n}`);
            params.set('rspn', '0');
          }

          const response = await fetch(
            `https://geocode-maps.yandex.ru/v1/?${params.toString()}`
          );
          if (!response.ok) throw new Error(`geocoder_http_${response.status}`);

          const data = await response.json();
          const members =
            data &&
            data.response &&
            data.response.GeoObjectCollection &&
            data.response.GeoObjectCollection.featureMember;
          if (Array.isArray(members)) {
            const items = members
              .map((member) => {
                const object = member && member.GeoObject;
                const position = object && object.Point && object.Point.pos;
                if (!object || typeof position !== 'string') return null;

                const coordinates = position.split(/\s+/).map(Number);
                const longitude = coordinates[0];
                const latitude = coordinates[1];
                if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
                  return null;
                }

                const title = object.name || object.description || query;
                const subtitle =
                  object.description && object.description !== title
                    ? object.description
                    : null;
                return {
                  title,
                  subtitle,
                  searchText: [title, subtitle].filter(Boolean).join(', '),
                  latitude,
                  longitude,
                };
              })
              .filter(Boolean);
            if (items.length) return JSON.stringify(items);
          }
        } catch (error) {
          console.warn('Yandex HTTP geocoder failed:', error);
        }
      }

      // The JS API geocoder is the documented fallback and uses the key from
      // the already loaded API script.
      if (!window.ymaps) return '[]';
      try {
        await window.ymaps.ready();
        const options = { results: 20 };
        if (hasBounds) {
          options.boundedBy = [[s, w], [n, e]];
          options.strictBounds = false;
        }
        const result = await window.ymaps.geocode(query, options);
        const geoObjects = result && result.geoObjects;
        const items = [];
        if (geoObjects) {
          for (let i = 0; i < geoObjects.getLength(); i++) {
            const geoObject = geoObjects.get(i);
            const properties = geoObject.properties;
            const coordinates = geoObject.geometry.getCoordinates();
            if (!coordinates || coordinates.length < 2) continue;
            const title =
              properties.get('name') ||
              properties.get('text') ||
              query;
            const description = properties.get('description');
            items.push({
              title,
              subtitle: description && description !== title ? description : null,
              searchText: [title, description].filter(Boolean).join(', '),
              latitude: coordinates[0],
              longitude: coordinates[1],
            });
          }
        }
        return JSON.stringify(items);
      } catch (error) {
        console.error('Yandex place search failed:', error);
        return '[]';
      }
    },
    geocode(text, s, w, n, e) {
      return new Promise(resolve => {
        if (!window.ymaps) {
          console.warn('ymaps v2.1 not available for geocode');
          return resolve('null');
        }
        window.ymaps.ready(() => {
          const options = { results: 1 };
          if (Math.abs(n - s) > 0.0001 && Math.abs(e - w) > 0.0001) {
            options.boundedBy = [[s, w], [n, e]];
          }

          window.ymaps.geocode(text, options).then(res => {
            const first = res.geoObjects.get(0);
            if (!first) {
              console.warn('Geocode: no objects found for', text);
              return resolve('null');
            }
            const coords = first.geometry.getCoordinates();
            resolve(JSON.stringify({ latitude: coords[0], longitude: coords[1] }));
          }, (err) => {
            console.error('Geocode error:', err);
            resolve('null');
          });
        });
      });
    }
  };
})();
