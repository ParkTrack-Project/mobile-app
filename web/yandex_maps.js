(function () {
  const entries = new Map();
  const defaultCenter = [34.359757, 61.789114];
  const defaultZoom = 14;
  let renderingApi = null;
  let renderingLocale = null;
  let renderingPromise = null;
  let localeReloadPromise = null;
  let clusterModule = null;

  function normalizeLocale(locale) {
    return locale === 'en_RU' ? 'en_RU' : 'ru_RU';
  }

  function serviceApiKey() {
    const script = document.querySelector(
      'script[src*="api-maps.yandex.ru/2.1/"]'
    );
    if (!script || !script.src) return null;
    return new URL(script.src).searchParams.get('apikey');
  }

  function resetRenderingLoader() {
    const script = document.getElementById('yandex-maps-rendering');
    if (script) script.remove();
    try {
      delete window.ymaps3;
    } catch (_) {
      window.ymaps3 = undefined;
    }
    renderingApi = null;
    renderingLocale = null;
    renderingPromise = null;
    clusterModule = null;
  }

  function loadRenderingApi(locale) {
    const requestedLocale = normalizeLocale(locale);
    if (renderingApi && renderingLocale === requestedLocale) {
      return Promise.resolve(renderingApi);
    }
    if (renderingPromise && renderingLocale === requestedLocale) {
      return renderingPromise;
    }
    if (renderingApi && renderingLocale !== requestedLocale) {
      return reloadForLocale(requestedLocale).then(() => renderingApi);
    }

    const apiKey = serviceApiKey();
    if (!apiKey) return Promise.reject(new Error('missing_api_key'));

    renderingLocale = requestedLocale;
    renderingPromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.id = 'yandex-maps-rendering';
      script.src =
        `https://api-maps.yandex.ru/v3/?apikey=${encodeURIComponent(apiKey)}` +
        `&lang=${requestedLocale}`;
      script.onload = async () => {
        try {
          if (!window.ymaps3) throw new Error('rendering_api_unavailable');
          await window.ymaps3.ready;
          renderingApi = window.ymaps3;
          try {
            clusterModule = await renderingApi.import(
              '@yandex/ymaps3-clusterer'
            );
          } catch (_) {
            clusterModule = null;
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

  async function reloadForLocale(locale) {
    if (localeReloadPromise) return localeReloadPromise;
    localeReloadPromise = (async () => {
      const snapshots = [];
      for (const entry of entries.values()) {
        snapshots.push({
          entry,
          center: entry.map ? [...entry.map.center] : [...entry.center],
          zoom: entry.map ? entry.map.zoom : entry.zoom,
        });
        destroyMapInstance(entry);
      }
      resetRenderingLoader();
      await loadRenderingApi(locale);
      await Promise.all(
        snapshots
          .filter(({ entry }) => !entry.destroyed)
          .map(({ entry, center, zoom }) => {
            entry.locale = locale;
            return initializeMap(entry, center, zoom);
          })
      );
    })().finally(() => {
      localeReloadPromise = null;
    });
    return localeReloadPromise;
  }

  function destroyMapInstance(entry) {
    if (entry.map) entry.map.destroy();
    entry.map = null;
    entry.schemeLayer = null;
    entry.objects = [];
  }

  function emitCamera(entry) {
    if (!entry.map || !entry.map.center || !entry.map.bounds) return false;
    const center = entry.map.center;
    const bounds = entry.map.bounds;
    if (!bounds[0] || !bounds[1]) return false;
    entry.center = [...center];
    entry.zoom = entry.map.zoom;
    entry.onCamera(
      JSON.stringify({
        latitude: center[1],
        longitude: center[0],
        zoom: entry.map.zoom,
        west: bounds[0][0],
        south: bounds[0][1],
        east: bounds[1][0],
        north: bounds[1][1],
      })
    );
    return true;
  }

  function parkingLinePoints(points) {
    if (points.length < 4) return points;
    const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
    const midpoint = (a, b) => [
      (a[0] + b[0]) / 2,
      (a[1] + b[1]) / 2,
    ];
    if (distance(points[0], points[1]) <= distance(points[1], points[2])) {
      return [midpoint(points[0], points[1]), midpoint(points[2], points[3])];
    }
    return [midpoint(points[1], points[2]), midpoint(points[3], points[0])];
  }

  function addObject(entry, object) {
    entry.map.addChild(object);
    entry.objects.push(object);
    return object;
  }

  function parkingMarkerElement(zone, onTap) {
    const element = document.createElement('div');
    element.style.cssText = [
      'position:absolute',
      'left:-12px',
      'top:-12px',
      'width:24px',
      'height:24px',
      'box-sizing:border-box',
      'border:1px solid #fff',
      'border-radius:50%',
      `background:${zone.color}`,
      'display:flex',
      'align-items:center',
      'justify-content:center',
      'color:#fff',
      'font:700 9.5px/1 Roboto,Arial,sans-serif',
      'cursor:pointer',
      'box-shadow:0 1px 3px rgba(0,0,0,.35)',
      `opacity:${zone.opacity ?? 1}`,
    ].join(';');
    element.textContent = zone.label === null ? '' : String(zone.label);
    element.addEventListener('click', (event) => {
      event.stopPropagation();
      onTap();
    });
    return element;
  }

  function clusterMarkerElement(features, onTap) {
    const zones = features.map((feature) => feature.properties.zone);
    const opacity = zones.reduce(
      (maximum, zone) => Math.max(maximum, Number(zone.opacity ?? 1)),
      0
    );
    const forecastZones = zones.filter((zone) => zone.hasForecast);
    const freeCount = forecastZones.length
      ? forecastZones.reduce((sum, zone) => sum + Number(zone.freeCount || 0), 0)
      : null;
    const element = document.createElement('div');
    element.style.cssText = [
      'position:absolute',
      'left:-16px',
      'top:-16px',
      'width:32px',
      'height:32px',
      'box-sizing:border-box',
      'border:1px solid #fff',
      'border-radius:50%',
      `background:${freeCount === null ? '#757575' : freeCount > 0 ? '#2e7d32' : '#d32f2f'}`,
      'display:flex',
      'align-items:center',
      'justify-content:center',
      'text-align:center',
      'white-space:pre-line',
      'color:#fff',
      'font:700 9px/1.1 Roboto,Arial,sans-serif',
      'cursor:pointer',
      'box-shadow:0 1px 4px rgba(0,0,0,.4)',
      `opacity:${opacity}`,
    ].join(';');
    element.textContent = freeCount === null
      ? String(features.length)
      : `${freeCount}\n(${features.length})`;
    element.addEventListener('click', (event) => {
      event.stopPropagation();
      onTap();
    });
    return element;
  }

  function dotElement(color) {
    const element = document.createElement('div');
    element.style.cssText = [
      'position:absolute',
      'left:-8px',
      'top:-8px',
      'width:16px',
      'height:16px',
      'box-sizing:border-box',
      'border:1.5px solid #fff',
      'border-radius:50%',
      `background:${color}`,
      'box-shadow:0 1px 4px rgba(0,0,0,.4)',
    ].join(';');
    return element;
  }

  function navigationElement(angle) {
    const element = document.createElement('div');
    element.style.cssText =
      'position:absolute;left:-14px;top:-14px;width:28px;height:28px';
    element.innerHTML =
      '<svg viewBox="0 0 80 80" width="28" height="28" ' +
      `style="filter:drop-shadow(0 1px 2px rgba(0,0,0,.45));transform:rotate(${Number(angle) || 0}deg)">` +
      '<path d="M40 4 L62.4 57.6 L40 44.8 L17.6 57.6 Z" ' +
      'fill="#007aff" stroke="#fff" stroke-width="3" stroke-linejoin="round"/>' +
      '</svg>';
    return element;
  }

  function renderZoneShapes(entry, zones) {
    const { YMapFeature } = renderingApi;
    for (const zone of zones) {
      if (!zone.points || zone.points.length < 2) continue;
      const isLine = zone.type === 'line' || zone.points.length < 3;
      const coordinates = (isLine ? parkingLinePoints(zone.points) : zone.points)
        .map((point) => [point[1], point[0]]);
      const strokeWidth = zone.active ? 9 : zone.candidate ? 8 : 5;
      const strokes = zone.active || zone.candidate
        ? [
            { color: '#ffffff', width: strokeWidth + 2, opacity: zone.opacity ?? 1 },
            { color: zone.color, width: strokeWidth - 2, opacity: zone.opacity ?? 1 },
          ]
        : [{ color: zone.color, width: strokeWidth, opacity: zone.opacity ?? 1 }];
      const geometry = isLine
        ? { type: 'LineString', coordinates }
        : { type: 'Polygon', coordinates: [coordinates] };
      addObject(
        entry,
        new YMapFeature({
          id: `parktrack-zone-${zone.id}`,
          geometry,
          style: {
            stroke: strokes,
            fill: isLine ? undefined : `${zone.color}80`,
            fillOpacity: zone.opacity ?? 1,
            cursor: 'pointer',
            interactive: true,
          },
          onClick: () => entry.onZoneTap(zone.id),
        })
      );
    }
  }

  function renderParkingMarkers(entry, zones) {
    const { YMapMarker } = renderingApi;
    if (!clusterModule || zones.length < 2) {
      for (const zone of zones) {
        addObject(
          entry,
          new YMapMarker(
            {
              coordinates: [zone.center[1], zone.center[0]],
              zIndex: zone.active || zone.candidate ? 2200 : 2100,
            },
            parkingMarkerElement(zone, () => entry.onZoneTap(zone.id))
          )
        );
      }
      return;
    }

    const { YMapClusterer, clusterByGrid } = clusterModule;
    const features = zones.map((zone) => ({
      type: 'Feature',
      id: String(zone.id),
      geometry: {
        type: 'Point',
        coordinates: [zone.center[1], zone.center[0]],
      },
      properties: { zone },
    }));
    const clusterer = new YMapClusterer({
      method: clusterByGrid({ gridSize: 128 }),
      features,
      maxZoom: 15,
      marker: (feature) => {
        const zone = feature.properties.zone;
        return new YMapMarker(
          {
            source: entry.clusterSourceId,
            coordinates: feature.geometry.coordinates,
          },
          parkingMarkerElement(zone, () => entry.onZoneTap(zone.id))
        );
      },
      cluster: (coordinates, clusterFeatures) =>
        new YMapMarker(
          { source: entry.clusterSourceId, coordinates },
          clusterMarkerElement(clusterFeatures, () => {
            entry.map.setLocation({
              center: coordinates,
              zoom: Math.min(entry.map.zoom + 2, 17),
              duration: 300,
            });
          })
        ),
    });
    addObject(entry, clusterer);
  }

  function render(entry, state) {
    entry.latestState = state;
    if (!entry.map) return;
    const locale = normalizeLocale(state.locale || entry.locale);
    if (locale !== entry.locale) {
      reloadForLocale(locale).catch(() => entry.onError('map_load'));
      return;
    }

    const theme = state.theme === 'dark' ? 'dark' : 'light';
    if (theme !== entry.theme) {
      entry.theme = theme;
      entry.map.update({ theme });
      entry.schemeLayer.update({ theme });
    }

    for (const object of entry.objects) entry.map.removeChild(object);
    entry.objects = [];

    const zones = state.zones || [];
    renderZoneShapes(entry, zones);
    renderParkingMarkers(entry, zones);

    const { YMapFeature, YMapMarker } = renderingApi;
    if (state.route && state.route.length >= 2) {
      addObject(
        entry,
        new YMapFeature({
          id: 'parktrack-route',
          geometry: {
            type: 'LineString',
            coordinates: state.route.map((point) => [point[1], point[0]]),
          },
          style: {
            stroke: [
              { color: '#ffffff', width: 9, opacity: 0.9 },
              { color: '#2196f3', width: 6 },
            ],
          },
        })
      );
    }
    if (state.user) {
      addObject(
        entry,
        new YMapMarker(
          { coordinates: [state.user[1], state.user[0]], zIndex: 2300 },
          dotElement('#007aff')
        )
      );
    }
    if (state.destination) {
      addObject(
        entry,
        new YMapMarker(
          {
            coordinates: [state.destination[1], state.destination[0]],
            zIndex: 2300,
          },
          dotElement('#2e7d32')
        )
      );
    }
    if (state.navigation) {
      addObject(
        entry,
        new YMapMarker(
          {
            coordinates: [state.navigation[1], state.navigation[0]],
            zIndex: 2400,
          },
          navigationElement(state.navigation[2])
        )
      );
    }
  }

  async function initializeMap(entry, center = defaultCenter, zoom = defaultZoom) {
    if (entry.destroyed || entry.initializing) return;
    entry.initializing = true;
    entry.center = center;
    entry.zoom = zoom;
    try {
      const api = await loadRenderingApi(entry.locale);
      if (entry.destroyed) return;
      const {
        YMap,
        YMapDefaultSchemeLayer,
        YMapDefaultFeaturesLayer,
        YMapFeatureDataSource,
        YMapLayer,
        YMapListener,
      } = api;
      entry.map = new YMap(document.getElementById(entry.elementId), {
        location: { center, zoom },
        theme: entry.theme,
        mode: 'vector',
        behaviors: ['drag', 'scrollZoom', 'pinchZoom', 'dblClick'],
      });
      entry.schemeLayer = new YMapDefaultSchemeLayer({ theme: entry.theme });
      entry.map.addChild(entry.schemeLayer);
      entry.map.addChild(new YMapDefaultFeaturesLayer());
      if (clusterModule) {
        entry.map.addChild(
          new YMapFeatureDataSource({ id: entry.clusterSourceId })
        );
        entry.map.addChild(
          new YMapLayer({
            source: entry.clusterSourceId,
            type: 'markers',
            zIndex: 2000,
          })
        );
      }
      entry.map.addChild(
        new YMapListener({
          onUpdate: () => emitCamera(entry),
        })
      );
      if (entry.latestState) render(entry, entry.latestState);
      emitCamera(entry);
    } catch (_) {
      entry.onError('map_load');
    } finally {
      entry.initializing = false;
    }
  }

  function withServicesReady(action) {
    return new Promise((resolve, reject) => {
      if (!window.ymaps) {
        reject(new Error('services_api_unavailable'));
        return;
      }
      window.ymaps.ready(() => {
        Promise.resolve().then(action).then(resolve, reject);
      });
    });
  }

  function serializeSearchResults(geoObjects, fallbackText) {
    const items = [];
    const add = (geoObject) => {
      const properties = geoObject.properties;
      const metadata = properties.get('metaDataProperty') || {};
      const company = metadata.CompanyMetaData || {};
      const address =
        company.address ||
        properties.get('description') ||
        (typeof geoObject.getAddressLine === 'function'
          ? geoObject.getAddressLine()
          : '') ||
        '';
      const title =
        properties.get('name') ||
        company.name ||
        properties.get('text') ||
        address ||
        fallbackText;
      const coordinates =
        geoObject.geometry && geoObject.geometry.getCoordinates();
      if (!coordinates || coordinates.length < 2) return;
      items.push({
        title,
        subtitle: address && address !== title ? address : null,
        searchText: [title, address].filter(Boolean).join(', '),
        latitude: coordinates[0],
        longitude: coordinates[1],
      });
    };
    if (Array.isArray(geoObjects)) {
      geoObjects.forEach(add);
    } else if (geoObjects && typeof geoObjects.each === 'function') {
      geoObjects.each(add);
    }
    return items;
  }

  function geocodePlaces(text, south, west, north, east) {
    return window.ymaps
      .geocode(text, {
        boundedBy: [
          [south, west],
          [north, east],
        ],
        results: 10,
      })
      .then((result) => serializeSearchResults(result.geoObjects, text));
  }

  window.parkTrackYandexMaps = {
    create(elementId, locale, theme, onCamera, onZoneTap, onError) {
      const entry = {
        elementId,
        locale: normalizeLocale(locale),
        theme: theme === 'dark' ? 'dark' : 'light',
        onCamera,
        onZoneTap,
        onError,
        clusterSourceId: `parktrack-clusters-${elementId}`,
        map: null,
        schemeLayer: null,
        objects: [],
        latestState: null,
        center: [...defaultCenter],
        zoom: defaultZoom,
        initializing: false,
        destroyed: false,
      };
      entries.set(elementId, entry);
      initializeMap(entry);
    },

    update(elementId, stateJson) {
      const entry = entries.get(elementId);
      if (entry) render(entry, JSON.parse(stateJson));
    },

    move(elementId, latitude, longitude, zoom) {
      const entry = entries.get(elementId);
      if (!entry || !entry.map) return;
      entry.map.setLocation({
        center: [longitude, latitude],
        zoom,
        duration: 300,
      });
    },

    setZoom(elementId, zoom) {
      const entry = entries.get(elementId);
      if (!entry || !entry.map) return;
      entry.map.setLocation({ zoom, duration: 200 });
    },

    retry(elementId) {
      const entry = entries.get(elementId);
      if (!entry) return;
      const center = entry.map ? [...entry.map.center] : [...entry.center];
      const zoom = entry.map ? entry.map.zoom : entry.zoom;
      destroyMapInstance(entry);
      if (!renderingApi) resetRenderingLoader();
      initializeMap(entry, center, zoom);
    },

    destroy(elementId) {
      const entry = entries.get(elementId);
      if (!entry) return;
      entry.destroyed = true;
      destroyMapInstance(entry);
      entries.delete(elementId);
    },

    suggest(text, south, west, north, east) {
      return withServicesReady(() => {
        const searchControl = new window.ymaps.control.SearchControl({
          options: {
            provider: 'yandex#search',
            boundedBy: [
              [south, west],
              [north, east],
            ],
            results: 10,
            noPopup: true,
            noSuggestPanel: true,
            useMapBounds: false,
          },
        });
        return searchControl.search(text).then(
          () => {
            const items = serializeSearchResults(
              searchControl.getResultsArray(),
              text
            );
            searchControl.clear();
            return items.length
              ? items
              : geocodePlaces(text, south, west, north, east);
          },
          () => geocodePlaces(text, south, west, north, east)
        );
      }).then((items) => JSON.stringify(items));
    },

    geocode(text, south, west, north, east) {
      return withServicesReady(() =>
        window.ymaps.geocode(text, {
          boundedBy: [
            [south, west],
            [north, east],
          ],
          results: 1,
        })
      ).then((result) => {
        const geoObject = result.geoObjects.get(0);
        if (!geoObject) return 'null';
        const coordinates = geoObject.geometry.getCoordinates();
        if (!coordinates || coordinates.length < 2) return 'null';
        return JSON.stringify({
          latitude: coordinates[0],
          longitude: coordinates[1],
        });
      });
    },

    reverseGeocode(latitude, longitude) {
      return withServicesReady(() =>
        window.ymaps.geocode([latitude, longitude], { results: 1 })
      ).then((result) => {
        const geoObject = result.geoObjects.get(0);
        const address =
          geoObject && typeof geoObject.getAddressLine === 'function'
            ? geoObject.getAddressLine()
            : null;
        return JSON.stringify(address || null);
      });
    },

    route(fromLatitude, fromLongitude, toLatitude, toLongitude) {
      return withServicesReady(() =>
        window.ymaps.route(
          [
            [fromLatitude, fromLongitude],
            [toLatitude, toLongitude],
          ],
          { mapStateAutoApply: false, routingMode: 'auto' }
        )
      ).then((route) => {
        const points = [];
        route.getPaths().each((path) => {
          for (const point of path.geometry.getCoordinates() || []) {
            const previous = points[points.length - 1];
            if (
              !previous ||
              previous[0] !== point[0] ||
              previous[1] !== point[1]
            ) {
              points.push(point);
            }
          }
        });
        const duration =
          typeof route.getJamsTime === 'function'
            ? route.getJamsTime()
            : typeof route.getTime === 'function'
              ? route.getTime()
              : 0;
        const distance =
          typeof route.getLength === 'function' ? route.getLength() : 0;
        return JSON.stringify({ points, duration, distance });
      });
    },
  };
})();
