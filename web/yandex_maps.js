(function () {
  const entries = new Map();
  const defaultCenter = [34.359757, 61.789114]; // [lon, lat] for v3
  const defaultZoom = 14;

  let renderingApi = null;
  let renderingLocale = null;
  let renderingPromise = null;
  let routerApiConfigured = false;
  const searchConfigPromises = new Map();
  let searchJsonpSequence = 0;
  const yandexRouteTimeoutMs = 4000;
  const osrmRouteTimeoutMs = 30000;
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

  function routerApiKey() {
    const meta = document.querySelector('meta[name="yandex-router-api-key"]');
    const value = meta && typeof meta.content === 'string'
      ? meta.content.trim()
      : '';
    return value || null;
  }

  function configureRouterApi(api) {
    if (routerApiConfigured) return true;
    const routerKey = routerApiKey();
    if (!routerKey) return false;
    api.getDefaultConfig().setApikeys({ router: routerKey });
    routerApiConfigured = true;
    return true;
  }

  function serviceSearchLocale(locale) {
    return locale === 'ru_RU' ? 'ru_RU' : 'en_US';
  }

  function withTimeout(promise, timeoutMs, errorCode) {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error(errorCode)), timeoutMs);
      Promise.resolve(promise).then(
        value => {
          clearTimeout(timeout);
          resolve(value);
        },
        error => {
          clearTimeout(timeout);
          reject(error);
        }
      );
    });
  }

  async function routeViaOsrm(fLat, fLon, tLat, tLon) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), osrmRouteTimeoutMs);
    try {
      const coordinates =
        `${encodeURIComponent(fLon)},${encodeURIComponent(fLat)};` +
        `${encodeURIComponent(tLon)},${encodeURIComponent(tLat)}`;
      const response = await fetch(
        `https://router.project-osrm.org/route/v1/driving/${coordinates}` +
          '?overview=simplified&geometries=geojson&steps=false',
        { signal: controller.signal }
      );
      if (!response.ok) throw new Error(`osrm_route_http_${response.status}`);
      const payload = await response.json();
      const route =
        payload && payload.code === 'Ok' && Array.isArray(payload.routes)
          ? payload.routes[0]
          : null;
      const rawCoordinates =
        route &&
        route.geometry &&
        Array.isArray(route.geometry.coordinates)
          ? route.geometry.coordinates
          : [];
      const points = rawCoordinates
        .filter(coordinate =>
          Array.isArray(coordinate) &&
          coordinate.length >= 2 &&
          Number.isFinite(Number(coordinate[0])) &&
          Number.isFinite(Number(coordinate[1]))
        )
        .map(coordinate => [Number(coordinate[1]), Number(coordinate[0])]);
      if (points.length < 2) throw new Error('osrm_route_empty');
      return {
        points,
        duration: Number(route.duration) || 0,
        distance: Number(route.distance) || 0,
      };
    } finally {
      clearTimeout(timeout);
    }
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
          if (routerApiKey() && !routerApiConfigured) {
            try {
              configureRouterApi(window.ymaps3);
            } catch (error) {
              console.warn('Yandex Router API configuration failed:', error);
            }
          }
          renderingApi = window.ymaps3;
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
    if (entry.cameraFrame != null) {
      cancelAnimationFrame(entry.cameraFrame);
      entry.cameraFrame = null;
    }
    if (entry.userAnimationFrame != null) {
      cancelAnimationFrame(entry.userAnimationFrame);
      entry.userAnimationFrame = null;
    }
    if (entry.promoFrame != null) {
      cancelAnimationFrame(entry.promoFrame);
      entry.promoFrame = null;
    }
    if (entry.zoneRenderTimer != null) {
      clearTimeout(entry.zoneRenderTimer);
      entry.zoneRenderTimer = null;
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
    entry.userAccuracyObject = null;
    entry.userMarkerObject = null;
    entry.userMarkerElement = null;
    entry.userMarkerHasHeading = false;
    entry.userMarkerCoordinates = null;
    entry.userAnimationFrame = null;
    entry.userAnimation = null;
    entry.navigationMarkerObject = null;
    entry.navigationMarkerElement = null;
    entry.destinationMarkerObject = null;
    entry.destinationMarkerElement = null;
    entry.zoneRenderSignature = null;
    entry.renderedZoomBucket = null;
    entry.routeSignature = null;
    entry.positionSignature = null;
    entry.lastCameraKey = null;
  }

  function emitCamera(entry, mapInAction = false) {
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
      mapInAction ? 1 : 0,
      entry.userGestureActive ? 1 : 0,
    ]
      .map((value) => Number(value).toFixed(7))
      .join('|');

    const userGesture = Boolean(entry.userGestureActive);
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
      cameraUpdateFinished: !mapInAction,
      userGesture,
    }));
    if (!mapInAction) entry.userGestureActive = false;
    return true;
  }

  function scheduleCameraEmit(entry, mapInAction) {
    if (entry.destroyed) return;
    entry.cameraInAction = Boolean(mapInAction);
    if (entry.cameraFrame != null) return;
    entry.cameraFrame = requestAnimationFrame(() => {
      entry.cameraFrame = null;
      emitCamera(entry, entry.cameraInAction);
    });
  }

  function scheduleZoneRender(entry) {
    if (entry.destroyed || entry.zoneRenderTimer != null) return;
    entry.zoneRenderTimer = setTimeout(() => {
      entry.zoneRenderTimer = null;
      if (entry.latestState) render(entry, entry.latestState);
    }, 400);
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

  const parkingMarkerScaleFactor = 1.3;
  function parkingMarkerElement(zone, onTap) {
    const el = document.createElement('div');
    el.className = 'parktrack-marker';
    const zIndex = zone.active ? 2300 : zone.candidate ? 2200 : 2100;
    el.style.cssText = `position:absolute;left:0;top:0;transform:translate(-50%,-50%);min-width:${20 * parkingMarkerScaleFactor}px;height:${20 * parkingMarkerScaleFactor}px;box-sizing:border-box;border:0;border-radius:9999px;padding:${2 * parkingMarkerScaleFactor}px ${6 * parkingMarkerScaleFactor}px;background:${zone.stroke};display:flex;align-items:center;justify-content:center;color:${zone.markerTextColor};font:600 ${12 * parkingMarkerScaleFactor}px/${16 * parkingMarkerScaleFactor}px Roboto,Arial,sans-serif;white-space:nowrap;cursor:pointer;box-shadow:0 1px 3px rgba(0,0,0,.1),0 1px 2px rgba(0,0,0,.1);opacity:${zone.markerOpacity ?? 1};z-index:${zIndex}`;
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
    return Math.min(28 + Math.floor(zoneCount / 4) * 4, 44) *
      parkingMarkerScaleFactor;
  }

  function clusterMarkerElement(zones, onTap) {
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
    const fontSize = size >= 38 * parkingMarkerScaleFactor ? 19 : 17;
    el.style.cssText = `position:absolute;left:0;top:0;transform:translate(-50%,-50%);width:${size}px;height:${size}px;box-sizing:border-box;border:0;border-radius:9999px;background:${color};display:flex;align-items:center;justify-content:center;text-align:center;color:${zones[0].markerTextColor};font:800 ${fontSize}px/1 Roboto,Arial,sans-serif;cursor:pointer;box-shadow:0 4px 6px -1px rgba(0,0,0,.1),0 2px 4px -2px rgba(0,0,0,.1),0 0 0 2px rgba(255,255,255,.7);opacity:${opacity};z-index:2100`;
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

  function clusterZoomBucket(zoom) {
    return Math.floor(Number(zoom || 0) / 0.5) * 0.5;
  }

  function clusterFreeCap(zoom) {
    if (zoom < 7) return 1400;
    if (zoom < 10) return 350;
    if (zoom < 13) return 150;
    return Infinity;
  }

  function connectedParkingGroups(points) {
    const parents = points.map((_, index) => index);
    const cells = new Map();
    const root = (index) => {
      while (parents[index] !== index) {
        parents[index] = parents[parents[index]];
        index = parents[index];
      }
      return index;
    };
    const union = (left, right) => {
      const leftRoot = root(left);
      const rightRoot = root(right);
      if (leftRoot !== rightRoot) parents[rightRoot] = leftRoot;
    };
    for (let index = 0; index < points.length; index++) {
      const point = points[index];
      const cellX = Math.floor(point.pixel[0] / 22);
      const cellY = Math.floor(point.pixel[1] / 22);
      for (let dx = -1; dx <= 1; dx++) {
        for (let dy = -1; dy <= 1; dy++) {
          const neighbours = cells.get(`${cellX + dx}:${cellY + dy}`) || [];
          for (const other of neighbours) {
            const deltaX = points[other].pixel[0] - point.pixel[0];
            const deltaY = points[other].pixel[1] - point.pixel[1];
            if (deltaX * deltaX + deltaY * deltaY <= 22 * 22) {
              union(index, other);
            }
          }
        }
      }
      const key = `${cellX}:${cellY}`;
      const cell = cells.get(key) || [];
      cell.push(index);
      cells.set(key, cell);
    }
    const groups = new Map();
    points.forEach((point, index) => {
      const key = root(index);
      const group = groups.get(key) || [];
      group.push(point);
      groups.set(key, group);
    });
    return [...groups.values()];
  }

  function splitParkingGroupByCap(points, cap) {
    const freeSum = points.reduce(
      (sum, point) =>
        sum + (point.zone.isActive
          ? Math.max(0, Number(point.zone.freeCount || 0))
          : 0),
      0
    );
    if (points.length <= 1 || freeSum <= cap) return [points];
    const xs = points.map(point => point.pixel[0]);
    const ys = points.map(point => point.pixel[1]);
    const splitOnX =
      Math.max(...xs) - Math.min(...xs) >= Math.max(...ys) - Math.min(...ys);
    const sorted = [...points].sort((left, right) => {
      const delta = splitOnX
        ? left.pixel[0] - right.pixel[0]
        : left.pixel[1] - right.pixel[1];
      return delta || Number(left.zone.id) - Number(right.zone.id);
    });
    const midpoint = Math.floor(sorted.length / 2);
    return [
      ...splitParkingGroupByCap(sorted.slice(0, midpoint), cap),
      ...splitParkingGroupByCap(sorted.slice(midpoint), cap),
    ];
  }

  function meanParkingCenter(points) {
    return [
      points.reduce((sum, point) => sum + point.coordinates[0], 0) /
        points.length,
      points.reduce((sum, point) => sum + point.coordinates[1], 0) /
        points.length,
    ];
  }

  function mergeOverlappingParkingGroups(groups, zoom) {
    let current = groups;
    while (current.length > 1) {
      const parents = current.map((_, index) => index);
      const root = (index) => {
        while (parents[index] !== index) {
          parents[index] = parents[parents[index]];
          index = parents[index];
        }
        return index;
      };
      const centers = current.map(group =>
        worldPixel(meanParkingCenter(group), zoom)
      );
      let merged = false;
      for (let left = 0; left < current.length; left++) {
        for (let right = left + 1; right < current.length; right++) {
          const minimumDistance =
            clusterSize(current[left].length) / 2 + 2 +
            clusterSize(current[right].length) / 2 + 2;
          const dx = centers[left][0] - centers[right][0];
          const dy = centers[left][1] - centers[right][1];
          if (Math.hypot(dx, dy) < minimumDistance) {
            const leftRoot = root(left);
            const rightRoot = root(right);
            if (leftRoot !== rightRoot) {
              parents[rightRoot] = leftRoot;
              merged = true;
            }
          }
        }
      }
      if (!merged) return current;
      const next = new Map();
      current.forEach((group, index) => {
        const key = root(index);
        next.set(key, [...(next.get(key) || []), ...group]);
      });
      current = [...next.values()];
    }
    return current;
  }

  function clusterParkingZones(zones, zoom, quantize = true) {
    const effectiveZoom = quantize ? clusterZoomBucket(zoom) : zoom;
    const points = zones
      .filter(zone => Array.isArray(zone.center) && zone.center.length === 2)
      .map(zone => {
        const coordinates = [Number(zone.center[1]), Number(zone.center[0])];
        return {
          zone,
          coordinates,
          pixel: worldPixel(coordinates, effectiveZoom),
        };
      });
    const splitGroups = connectedParkingGroups(points).flatMap(group =>
      splitParkingGroupByCap(group, clusterFreeCap(effectiveZoom))
    );
    const singletonIds = new Set();
    let aggregateGroups = [];
    for (const group of splitGroups) {
      if (group.length === 1) singletonIds.add(group[0].zone.id);
      else aggregateGroups.push(group);
    }
    aggregateGroups = mergeOverlappingParkingGroups(
      aggregateGroups,
      effectiveZoom
    );
    const clusters = aggregateGroups.map(group => {
      const zonesInCluster = group.map(point => point.zone);
      const zoneIds = zonesInCluster.map(zone => zone.id).sort((a, b) => a - b);
      return {
        key: zoneIds.join('-'),
        center: meanParkingCenter(group),
        zoneIds,
        zones: zonesInCluster,
      };
    }).sort((left, right) => left.key.localeCompare(right.key));
    return { zoom: effectiveZoom, clusters, singletonIds };
  }

  const parkingCounterMinZoom = 14;

  function clusterExpansionZoom(zones, clusterZoneIds, currentZoom) {
    const firstZoom = clusterZoomBucket(currentZoom) + 0.5;
    for (let zoom = firstZoom; zoom <= 21; zoom += 0.5) {
      const result = clusterParkingZones(zones, zoom);
      const remainsOneCluster = result.clusters.some(cluster =>
        clusterZoneIds.every(zoneId => cluster.zoneIds.includes(zoneId))
      );
      const hasHiddenSingleton = zoom < parkingCounterMinZoom &&
        clusterZoneIds.some(zoneId => result.singletonIds.has(zoneId));
      if (!remainsOneCluster && !hasHiddenSingleton) return zoom;
    }
    return 21;
  }

  function zonesInsideBounds(zones, bounds) {
    if (!bounds || !bounds[0] || !bounds[1]) return zones;
    const west = Number(bounds[0][0]);
    const east = Number(bounds[1][0]);
    const firstLatitude = Number(bounds[0][1]);
    const secondLatitude = Number(bounds[1][1]);
    if (
      !Number.isFinite(west) ||
      !Number.isFinite(east) ||
      !Number.isFinite(firstLatitude) ||
      !Number.isFinite(secondLatitude)
    ) {
      return zones;
    }
    // YMap bounds use [west, north], [east, south]. Normalize the latitude
    // values as a guard against API/version-specific corner ordering.
    const south = Math.min(firstLatitude, secondLatitude);
    const north = Math.max(firstLatitude, secondLatitude);
    return zones.filter(zone => {
      if (!Array.isArray(zone.center) || zone.center.length !== 2) return false;
      const latitude = Number(zone.center[0]);
      const longitude = Number(zone.center[1]);
      const insideLongitude = west <= east
        ? longitude >= west && longitude <= east
        : longitude >= west || longitude <= east;
      return (
        Number.isFinite(latitude) &&
        Number.isFinite(longitude) &&
        latitude >= south &&
        latitude <= north &&
        insideLongitude
      );
    });
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

  function accuracyCircleCoordinates(latitude, longitude, radiusMeters) {
    const earthRadiusMeters = 6378137;
    const angularDistance = radiusMeters / earthRadiusMeters;
    const latitudeRadians = latitude * Math.PI / 180;
    const longitudeRadians = longitude * Math.PI / 180;
    const ring = [];
    const segments = 48;

    for (let index = 0; index <= segments; index += 1) {
      const bearing = index * 2 * Math.PI / segments;
      const targetLatitude = Math.asin(
        Math.sin(latitudeRadians) * Math.cos(angularDistance) +
        Math.cos(latitudeRadians) * Math.sin(angularDistance) *
          Math.cos(bearing)
      );
      const targetLongitude = longitudeRadians + Math.atan2(
        Math.sin(bearing) * Math.sin(angularDistance) *
          Math.cos(latitudeRadians),
        Math.cos(angularDistance) -
          Math.sin(latitudeRadians) * Math.sin(targetLatitude)
      );
      const normalizedLongitude =
        ((targetLongitude * 180 / Math.PI + 540) % 360) - 180;
      ring.push([normalizedLongitude, targetLatitude * 180 / Math.PI]);
    }

    return ring;
  }

  function removeMapObject(entry, object) {
    if (!entry.map || !object) return;
    try { entry.map.removeChild(object); } catch (_) {}
  }

  function updateMapObject(object, props) {
    if (!object || typeof object.update !== 'function') return false;
    try {
      object.update(props);
      return true;
    } catch (_) {
      return false;
    }
  }

  function interpolateCoordinates(from, to, t) {
    const clamped = Math.max(0, Math.min(1, t));
    let deltaLon = to[0] - from[0];
    if (deltaLon > 180) deltaLon -= 360;
    if (deltaLon < -180) deltaLon += 360;
    const lon = ((((from[0] + deltaLon * clamped) + 180) % 360) + 360) % 360 - 180;
    return [
      lon,
      from[1] + (to[1] - from[1]) * clamped,
    ];
  }

  function updateUserMarkerHeading(entry, heading) {
    if (!entry.userMarkerElement) return;
    if (Number.isFinite(heading)) {
      const azimuth = entry.map ? Number(entry.map.azimuth || 0) : 0;
      entry.userMarkerElement.style.setProperty(
        '--heading',
        `${heading - azimuth - 90}deg`
      );
    }
  }

  function userAccuracyFeature(latitude, longitude, radiusMeters) {
    return {
      geometry: {
        type: 'Polygon',
        coordinates: [[
          ...accuracyCircleCoordinates(latitude, longitude, radiusMeters),
        ]],
      },
      style: {
        stroke: [{ color: 'rgba(255, 59, 48, 0.60)', width: 2 }],
        fill: 'rgba(255, 59, 48, 0.14)',
      },
    };
  }

  function updateUserAccuracy(entry, latitude, longitude, userAccuracy) {
    const { YMapFeature } = renderingApi;
    if (userAccuracy == null) {
      removeMapObject(entry, entry.userAccuracyObject);
      entry.userAccuracyObject = null;
      return;
    }
    const props = userAccuracyFeature(latitude, longitude, userAccuracy);
    if (entry.userAccuracyObject) {
      if (!updateMapObject(entry.userAccuracyObject, props)) {
        removeMapObject(entry, entry.userAccuracyObject);
        entry.userAccuracyObject = addObject(
          entry,
          new YMapFeature(props),
          'positionObjects'
        );
      }
      return;
    }
    entry.userAccuracyObject = addObject(
      entry,
      new YMapFeature(props),
      'positionObjects'
    );
  }

  function createUserMarkerElement(hasUserHeading, heading) {
    ensureUserLocationStyles();
    const el = document.createElement('div');
    el.className = 'parktrack-user-location';
    el.setAttribute('aria-label', 'Your location');
    el.innerHTML =
      (hasUserHeading
        ? '<span class="parktrack-user-location__direction"></span>'
        : '') +
      '<span class="parktrack-user-location__point"></span>';
    if (hasUserHeading) {
      el.style.setProperty('--heading', `${heading - 90}deg`);
    }
    return el;
  }

  function setUserMarkerCoordinates(entry, coordinates, heading, userAccuracy) {
    if (!entry.userMarkerObject) return;
    if (!updateMapObject(entry.userMarkerObject, { coordinates })) {
      const { YMapMarker } = renderingApi;
      removeMapObject(entry, entry.userMarkerObject);
      entry.userMarkerObject = addObject(
        entry,
        new YMapMarker({ coordinates }, entry.userMarkerElement),
        'positionObjects'
      );
    }
    entry.userMarkerCoordinates = coordinates;
    updateUserMarkerHeading(entry, heading);
    updateUserAccuracy(entry, coordinates[1], coordinates[0], userAccuracy);
  }

  function animateUserMarker(entry, to, heading, userAccuracy) {
    const from = entry.userMarkerCoordinates || to;
    if (entry.userAnimationFrame != null) {
      cancelAnimationFrame(entry.userAnimationFrame);
      entry.userAnimationFrame = null;
    }
    const distance =
      Math.abs(from[0] - to[0]) + Math.abs(from[1] - to[1]);
    if (distance < 0.000001) {
      setUserMarkerCoordinates(entry, to, heading, userAccuracy);
      return;
    }
    entry.userAnimation = {
      from,
      to,
      startedAt: performance.now(),
      duration: 950,
      heading,
      userAccuracy,
    };
    const tick = (now) => {
      if (!entry.userAnimation || entry.destroyed) {
        entry.userAnimationFrame = null;
        return;
      }
      const animation = entry.userAnimation;
      const rawT = (now - animation.startedAt) / animation.duration;
      const t = Math.max(0, Math.min(1, rawT));
      const eased = t < 0.5
        ? 4 * t * t * t
        : 1 - Math.pow(-2 * t + 2, 3) / 2;
      const coordinates = interpolateCoordinates(
        animation.from,
        animation.to,
        eased
      );
      setUserMarkerCoordinates(
        entry,
        coordinates,
        animation.heading,
        animation.userAccuracy
      );
      if (t < 1) {
        entry.userAnimationFrame = requestAnimationFrame(tick);
      } else {
        entry.userAnimationFrame = null;
        entry.userAnimation = null;
      }
    };
    entry.userAnimationFrame = requestAnimationFrame(tick);
  }

  function renderPositions(entry, state) {
    if (!entry.map || !renderingApi) return;
    const { YMapMarker } = renderingApi;
    const stateUserHeading =
      state.user && Number.isFinite(Number(state.user[2]))
        ? Number(state.user[2])
        : null;
    const effectiveUserHeading = entry.deviceHeading ?? stateUserHeading;
    const hasUserHeading = Number.isFinite(effectiveUserHeading);
    const userAccuracy =
      state.user && Number.isFinite(Number(state.user[3])) &&
      Number(state.user[3]) > 0
        ? Number(state.user[3])
        : null;
    const positionSignature = JSON.stringify([
      state.navigation || null,
      state.user
        ? [
            state.user[0],
            state.user[1],
            hasUserHeading ? effectiveUserHeading : null,
            userAccuracy,
          ]
        : null,
      state.destination || null,
      Number(entry.map.azimuth || 0),
    ]);
    if (positionSignature === entry.positionSignature) return;
    entry.positionSignature = positionSignature;

    if (state.navigation) {
      const angle = state.navigation[2] || 0;
      const coordinates = [state.navigation[1], state.navigation[0]];
      if (!entry.navigationMarkerElement) {
        entry.navigationMarkerElement = document.createElement('div');
        entry.navigationMarkerElement.style.cssText = `position:absolute;left:-14px;top:-14px;width:28px;height:28px;z-index:2400`;
      }
      entry.navigationMarkerElement.innerHTML = `<svg viewBox="0 0 80 80" width="28" height="28" style="filter:drop-shadow(0 1px 2px rgba(0,0,0,0.45));transform:rotate(${angle}deg)"><path d="M40 4 L62.4 57.6 L40 44.8 L17.6 57.6 Z" fill="#007aff" stroke="#fff" stroke-width="3" stroke-linejoin="round"/></svg>`;
      if (entry.navigationMarkerObject) {
        updateMapObject(entry.navigationMarkerObject, { coordinates });
      } else {
        entry.navigationMarkerObject = addObject(entry, new YMapMarker({
          coordinates
        }, entry.navigationMarkerElement), 'positionObjects');
      }
    } else {
      removeMapObject(entry, entry.navigationMarkerObject);
      entry.navigationMarkerObject = null;
    }
    if (state.user) {
      const coordinates = [Number(state.user[1]), Number(state.user[0])];
      if (userAccuracy != null) {
        updateUserAccuracy(entry, coordinates[1], coordinates[0], userAccuracy);
      }
      if (entry.userMarkerObject) {
        if (entry.userMarkerHasHeading !== hasUserHeading) {
          entry.userMarkerElement.innerHTML =
            (hasUserHeading
              ? '<span class="parktrack-user-location__direction"></span>'
              : '') +
            '<span class="parktrack-user-location__point"></span>';
          entry.userMarkerHasHeading = hasUserHeading;
        }
        animateUserMarker(entry, coordinates, effectiveUserHeading, userAccuracy);
      } else {
        entry.userMarkerElement = createUserMarkerElement(
          hasUserHeading,
          effectiveUserHeading
        );
        entry.userMarkerHasHeading = hasUserHeading;
        entry.userMarkerObject = addObject(entry, new YMapMarker({
          coordinates
        }, entry.userMarkerElement), 'positionObjects');
        entry.userMarkerCoordinates = coordinates;
        updateUserMarkerHeading(entry, effectiveUserHeading);
      }
    } else {
      if (entry.userAnimationFrame != null) {
        cancelAnimationFrame(entry.userAnimationFrame);
        entry.userAnimationFrame = null;
      }
      entry.userAnimation = null;
      removeMapObject(entry, entry.userAccuracyObject);
      removeMapObject(entry, entry.userMarkerObject);
      entry.userAccuracyObject = null;
      entry.userMarkerObject = null;
      entry.userMarkerElement = null;
      entry.userMarkerHasHeading = false;
      entry.userMarkerCoordinates = null;
    }
    if (state.destination) {
      const coordinates = [state.destination[1], state.destination[0]];
      if (!entry.destinationMarkerElement) {
        entry.destinationMarkerElement = document.createElement('div');
        entry.destinationMarkerElement.style.cssText = 'position:absolute;left:-16px;top:-40px;width:32px;height:40px;opacity:1;z-index:2300';
        entry.destinationMarkerElement.innerHTML = '<svg viewBox="0 0 32 40" width="32" height="40" style="filter:drop-shadow(0 2px 2px rgba(0,0,0,.35))"><path d="M16 39C13 32 4 24 4 14A12 12 0 0 1 28 14C28 24 19 32 16 39Z" fill="#2e7d32" stroke="#fff" stroke-width="2"/><circle cx="16" cy="14" r="4" fill="#fff"/></svg>';
      }
      if (entry.destinationMarkerObject) {
        updateMapObject(entry.destinationMarkerObject, { coordinates });
      } else {
        entry.destinationMarkerObject = addObject(entry, new YMapMarker({
          coordinates
        }, entry.destinationMarkerElement), 'positionObjects');
      }
    } else {
      removeMapObject(entry, entry.destinationMarkerObject);
      entry.destinationMarkerObject = null;
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

    const zones = zonesInsideBounds(state.zones || [], entry.map.bounds);
    const { YMapFeature, YMapMarker } = renderingApi;

    const zoomBucket = clusterZoomBucket(entry.map.zoom);
    const zoneRenderSignature = JSON.stringify([
      zoomBucket,
      zones.map(zone => [
        zone.id,
        zone.type,
        zone.points,
        zone.center,
        zone.freeCount,
        zone.isActive,
        zone.fill,
        zone.stroke,
        zone.active,
        zone.candidate,
        zone.markerOpacity,
        zone.markerTextColor,
        zone.clusterFull,
        zone.clusterOne,
        zone.clusterFree,
      ]),
    ]);
    if (zoneRenderSignature !== entry.zoneRenderSignature) {
      entry.zoneRenderSignature = zoneRenderSignature;
      entry.renderedZoomBucket = zoomBucket;
      clearObjectGroup(entry, 'zoneGeometryObjects');
      clearObjectGroup(entry, 'zoneMarkerObjects');
      entry.zoneFeatures.clear();
      const clustering = clusterParkingZones(zones, zoomBucket);
      const singletonZones = zones.filter(zone =>
        clustering.singletonIds.has(zone.id)
      );
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
          onClick: clustering.singletonIds.has(zone.id)
            ? () => {
                entry.zoneTapAt = performance.now();
                entry.onZoneTap(zone.id);
              }
            : undefined
        });
        entry.zoneFeatures.set(zone.id, feature);
        addObject(entry, feature, 'zoneGeometryObjects');
      }

      if (zoomBucket >= parkingCounterMinZoom) {
        for (const zone of singletonZones) {
          addObject(entry, new YMapMarker(
            { coordinates: [zone.center[1], zone.center[0]] },
            parkingMarkerElement(zone, () => {
              entry.zoneTapAt = performance.now();
              entry.onZoneTap(zone.id);
            })
          ), 'zoneMarkerObjects');
        }
      }
      for (const cluster of clustering.clusters) {
        addObject(entry, new YMapMarker(
          { coordinates: cluster.center },
          clusterMarkerElement(
            cluster.zones,
            () => entry.map.setLocation({
              center: cluster.center,
              zoom: clusterExpansionZoom(
                zones,
                cluster.zoneIds,
                entry.map.zoom
              ),
              duration: 300,
            })
          )
        ), 'zoneMarkerObjects');
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
        behaviors: [
          'drag',
          'scrollZoom',
          'pinchZoom',
          'pinchRotate',
          'dblClick'
        ]
      });
      entry.schemeLayer = new api.YMapDefaultSchemeLayer({ theme: entry.theme });
      entry.map.addChild(entry.schemeLayer);
      entry.map.addChild(new api.YMapDefaultFeaturesLayer());
      entry.map.addChild(new api.YMapListener({
        onUpdate: ({ mapInAction }) => {
          scheduleCameraEmit(entry, mapInAction);
          scheduleZoneRender(entry);
          if (entry.latestState) renderPositions(entry, entry.latestState);
          const zoomBucket = clusterZoomBucket(entry.map.zoom);
          if (
            entry.latestState &&
            zoomBucket !== entry.renderedZoomBucket
          ) {
            render(entry, entry.latestState);
          }
        },
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
        userAccuracyObject: null,
        userMarkerObject: null,
        userMarkerElement: null,
        userMarkerHasHeading: false,
        userMarkerCoordinates: null,
        userAnimationFrame: null,
        userAnimation: null,
        navigationMarkerObject: null,
        navigationMarkerElement: null,
        destinationMarkerObject: null,
        destinationMarkerElement: null,
        center: [...defaultCenter],
        zoom: defaultZoom,
        pendingPromoRoots: new Set(),
        cameraFrame: null,
        cameraInAction: false,
        zoneRenderTimer: null,
        promoFrame: null,
        zoneTapAt: 0,
        userGestureActive: false,
        latestStateJson: null,
        destroyed: false,
      };
      entries.set(elementId, entry);

      let pointerTracking = false;
      const markUserGesture = () => { entry.userGestureActive = true; };
      const startPointerTracking = () => { pointerTracking = true; };
      const stopPointerTracking = () => { pointerTracking = false; };
      const markPointerMove = () => {
        if (pointerTracking) markUserGesture();
      };
      element.addEventListener('pointerdown', startPointerTracking, { passive: true });
      element.addEventListener('pointermove', markPointerMove, { passive: true });
      element.addEventListener('pointerup', stopPointerTracking, { passive: true });
      element.addEventListener('pointercancel', stopPointerTracking, { passive: true });
      element.addEventListener('touchmove', markUserGesture, { passive: true });
      element.addEventListener('wheel', markUserGesture, { passive: true });
      element.addEventListener('dblclick', markUserGesture, { passive: true });
      entry.detachGestureListeners = () => {
        element.removeEventListener('pointerdown', startPointerTracking);
        element.removeEventListener('pointermove', markPointerMove);
        element.removeEventListener('pointerup', stopPointerTracking);
        element.removeEventListener('pointercancel', stopPointerTracking);
        element.removeEventListener('touchmove', markUserGesture);
        element.removeEventListener('wheel', markUserGesture);
        element.removeEventListener('dblclick', markUserGesture);
      };

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
    setZoom(id, z, durationMilliseconds) {
      const entry = entries.get(id);
      if (entry && entry.map) {
        entry.map.setLocation({
          zoom: z,
          duration: Math.max(0, Number(durationMilliseconds) || 0)
        });
      }
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
    fitBounds(id, south, west, north, east, azimuth, top, right, bottom, left) {
      const entry = entries.get(id);
      if (entry && entry.map) {
        entry.map.update({
          margin: [top || 0, right || 0, bottom || 0, left || 0]
        });
        entry.map.setLocation({
          bounds: [[west, south], [east, north]],
          azimuth,
          duration: 600
        });
      }
    },
    setCamera(id, lat, lon, zoom, azimuth, top, right, bottom, left) {
      const entry = entries.get(id);
      if (entry && entry.map) {
        entry.map.update({
          margin: [top || 0, right || 0, bottom || 0, left || 0]
        });
        entry.map.setLocation({
          center: [lon, lat],
          zoom,
          azimuth,
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
          duration: 600
        });
      }
    },
    follow(
      id,
      lat,
      lon,
      zoom,
      azimuth,
      top,
      right,
      bottom,
      left,
      durationMilliseconds
    ) {
      const entry = entries.get(id);
      if (entry && entry.map) {
        entry.map.update({
          margin: [top || 0, right || 0, bottom || 0, left || 0]
        });
        entry.map.setLocation({
          center: [lon, lat],
          zoom,
          azimuth,
          duration: Math.max(0, Number(durationMilliseconds) || 0)
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
        if (entry.detachGestureListeners) entry.detachGestureListeners();
        destroyMapInstance(entry);
        entries.delete(id);
      }
    },
    async route(fLat, fLon, tLat, tLon) {
      if (routerApiKey()) {
        try {
          const api = await loadRenderingApi(renderingLocale || 'ru_RU');
          if (typeof api.route !== 'function') {
            throw new Error('ymaps3_route_unavailable');
          }
          configureRouterApi(api);
          const responses = await withTimeout(
            api.route({
              points: [[fLon, fLat], [tLon, tLat]],
              type: 'driving',
            }),
            yandexRouteTimeoutMs,
            'ymaps3_route_timeout'
          );
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
          console.warn('Yandex Maps v3 route failed, using OSRM:', error);
        }
      }
      try {
        return JSON.stringify(await routeViaOsrm(fLat, fLon, tLat, tLon));
      } catch (error) {
        console.error('OSRM route failed:', error);
        return JSON.stringify({ points: [], duration: 0, distance: 0 });
      }
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
