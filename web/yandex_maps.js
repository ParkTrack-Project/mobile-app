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
    entry.zoneObjects = [];
    entry.routeObjects = [];
    entry.positionObjects = [];
    entry.zoneSignature = null;
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
    const cameraKey = [
      center[0],
      center[1],
      zoom,
      bounds[0][0],
      bounds[0][1],
      bounds[1][0],
      bounds[1][1],
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
    el.style.cssText = `position:absolute;left:-12px;top:-12px;width:24px;height:24px;box-sizing:border-box;border:1px solid #fff;border-radius:50%;background:${zone.color};display:flex;align-items:center;justify-content:center;color:#fff;font:700 9.5px/1 Roboto,Arial,sans-serif;cursor:pointer;box-shadow:0 1px 3px rgba(0,0,0,.35);opacity:${zone.opacity ?? 1};z-index:2100`;
    el.textContent = zone.label == null ? '' : String(zone.label);
    el.onclick = (e) => { e.stopPropagation(); onTap(); };
    return el;
  }

  function clusterMarkerElement(features, onTap) {
    const zones = features.map(f => f.properties.zone);
    const forecastZones = zones.filter((zone) => zone.hasForecast);
    const freeCount = forecastZones.length
      ? forecastZones.reduce(
          (sum, zone) => sum + Number(zone.freeCount ?? 0),
          0
        )
      : null;
    const el = document.createElement('div');
    el.className = 'parktrack-cluster';
    el.style.cssText = `position:absolute;left:-14px;top:-14px;width:28px;height:28px;box-sizing:border-box;border:1px solid #fff;border-radius:50%;background:${freeCount === null ? '#757575' : freeCount > 0 ? '#2e7d32' : '#d32f2f'};display:flex;align-items:center;justify-content:center;text-align:center;white-space:pre-line;color:#fff;font:700 8px/1.2 Roboto,Arial,sans-serif;cursor:pointer;box-shadow:0 1px 4px rgba(0,0,0,.4);z-index:2050`;
    el.textContent =
      freeCount === null
        ? `(${features.length})`
        : `${freeCount}\n(${features.length})`;
    el.onclick = (e) => { e.stopPropagation(); onTap(); };
    return el;
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

    const zoneSignature = JSON.stringify(zones);
    if (zoneSignature !== entry.zoneSignature) {
      entry.zoneSignature = zoneSignature;
      clearObjectGroup(entry, 'zoneObjects');

      for (const zone of zones) {
        if (!zone.points || zone.points.length < 2) continue;
        const isLine = zone.type === 'line' || zone.points.length < 3;
        const geometryPoints = isLine
          ? parkingLinePoints(zone.points)
          : zone.points;
        const coords = geometryPoints.map(p => [p[1], p[0]]);
        const highlighted = zone.active || zone.candidate;
        const stroke = highlighted
          ? [
              { color: '#ffffff', width: zone.active ? 10 : 9 },
              { color: zone.color, width: 6 },
            ]
          : [{ color: zone.color, width: isLine ? 6 : 2 }];
        addObject(entry, new YMapFeature({
          geometry: isLine
            ? { type: 'LineString', coordinates: coords }
            : { type: 'Polygon', coordinates: [coords] },
          style: {
            stroke,
            fill: isLine ? undefined : `${zone.color}80`,
          },
          onClick: () => entry.onZoneTap(zone.id)
        }), 'zoneObjects');
      }

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
              () => entry.onZoneTap(feature.properties.zone.id)
            )
          ),
          cluster: (coordinates, clusterFeatures) => new YMapMarker(
            { coordinates },
            clusterMarkerElement(clusterFeatures, () => entry.map.setLocation({
              center: coordinates,
              zoom: Math.min(entry.map.zoom + 2, 17),
              duration: 300,
            }))
          )
        }), 'zoneObjects');
      } else {
        for (const zone of zones) {
          addObject(entry, new YMapMarker(
            { coordinates: [zone.center[1], zone.center[0]] },
            parkingMarkerElement(zone, () => entry.onZoneTap(zone.id))
          ), 'zoneObjects');
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

    const positionSignature = JSON.stringify([
      state.navigation || null,
      state.user || null,
      state.destination || null,
    ]);
    if (positionSignature !== entry.positionSignature) {
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
        const el = document.createElement('div');
        el.style.cssText = `position:absolute;left:-8px;top:-8px;width:16px;height:16px;border:1.5px solid #fff;border-radius:50%;background:#007aff;box-shadow:0 1px 4px rgba(0,0,0,.4);z-index:2300`;
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
    create(element, locale, theme, onCamera, onZoneTap, onError) {
      const elementId = element.id;
      const entry = {
        element, locale: normalizeLocale(locale), theme,
        onCamera, onZoneTap, onError,
        map: null,
        zoneObjects: [],
        routeObjects: [],
        positionObjects: [],
        center: [...defaultCenter],
        zoom: defaultZoom,
        pendingPromoRoots: new Set(),
        cameraTimer: null,
        promoFrame: null,
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
    },
    update(id, state) {
      const entry = entries.get(id);
      if (!entry || state === entry.latestStateJson) return;
      entry.latestStateJson = state;
      render(entry, JSON.parse(state));
    },
    move(id, lat, lon, zoom) {
      const entry = entries.get(id);
      if (entry && entry.map) entry.map.setLocation({ center: [lon, lat], zoom, duration: 300 });
    },
    setZoom(id, z) {
      const entry = entries.get(id);
      if (entry && entry.map) entry.map.setLocation({ zoom: z, duration: 200 });
    },
    fitBounds(id, south, west, north, east) {
      const entry = entries.get(id);
      if (entry && entry.map) {
        entry.map.setLocation({
          bounds: [[west, south], [east, north]],
          duration: 600
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
        if (entry.observer) entry.observer.disconnect();
        destroyMapInstance(entry);
        entries.delete(id);
      }
    },
    route(fLat, fLon, tLat, tLon) {
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
