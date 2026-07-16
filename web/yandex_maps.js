(function () {
  const entries = new Map();

  function emitCamera(entry) {
    if (!entry.map) return false;
    const bounds = entry.map.getBounds();
    const center = entry.map.getCenter();
    if (!bounds || bounds.length < 2 || !center) return false;
    const latitudeSpan = Math.abs(bounds[1][0] - bounds[0][0]);
    const longitudeSpan = Math.abs(bounds[1][1] - bounds[0][1]);
    if (latitudeSpan < 0.000001 || longitudeSpan < 0.000001) return false;
    entry.onCamera(JSON.stringify({
      latitude: center[0],
      longitude: center[1],
      zoom: entry.map.getZoom(),
      west: bounds[0][1],
      south: bounds[0][0],
      east: bounds[1][1],
      north: bounds[1][0]
    }));
    return true;
  }

  function withYmapsReady(action) {
    return new Promise((resolve, reject) => {
      if (!window.ymaps) {
        reject(new Error('Yandex Maps API is not loaded'));
        return;
      }
      ymaps.ready(() => {
        Promise.resolve()
          .then(action)
          .then(resolve, reject);
      });
    });
  }

  function parkingLinePoints(points) {
    if (points.length < 4) return points;
    const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
    const midpoint = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    if (distance(points[0], points[1]) <= distance(points[1], points[2])) {
      return [midpoint(points[0], points[1]), midpoint(points[2], points[3])];
    }
    return [midpoint(points[1], points[2]), midpoint(points[3], points[0])];
  }

  function serializeSearchResults(geoObjects, fallbackText) {
    const items = [];
    const add = geoObject => {
      const properties = geoObject.properties;
      const metadata = properties.get('metaDataProperty') || {};
      const company = metadata.CompanyMetaData || {};
      const address = company.address
        || properties.get('description')
        || (typeof geoObject.getAddressLine === 'function' ? geoObject.getAddressLine() : '')
        || '';
      const title = properties.get('name')
        || company.name
        || properties.get('text')
        || address
        || fallbackText;
      const coordinates = geoObject.geometry && geoObject.geometry.getCoordinates();
      if (!coordinates || coordinates.length < 2) return;
      items.push({
        title,
        subtitle: address && address !== title ? address : null,
        searchText: [title, address].filter(Boolean).join(', '),
        latitude: coordinates[0],
        longitude: coordinates[1]
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
    return ymaps.geocode(text, {
      boundedBy: [[south, west], [north, east]],
      results: 10
    }).then(result => serializeSearchResults(result.geoObjects, text));
  }

  function styleClusters(entry) {
    if (!entry.clusterer) return;
    for (const cluster of entry.clusterer.getClusters()) {
      const markers = cluster.getGeoObjects();
      const forecastMarkers = markers.filter(marker => marker.properties.get('parkTrackHasForecast'));
      const totalFree = forecastMarkers.length === 0
        ? null
        : forecastMarkers.reduce(
            (sum, marker) => sum + Number(marker.properties.get('parkTrackFreeCount') || 0),
            0
          );
      const color = totalFree === null
        ? '#9e9e9e'
        : totalFree === 0
          ? '#e53935'
          : '#2e7d32';
      const label = totalFree === null
        ? `(${markers.length})`
        : markers.length <= 1
          ? String(totalFree)
          : `${totalFree}\n(${markers.length})`;
      cluster.properties.set('parkTrackColor', color);
      cluster.properties.set('parkTrackLabel', label);
    }
  }

  function render(entry, state) {
    if (!entry.map) {
      entry.pendingState = state;
      return;
    }
    entry.map.geoObjects.removeAll();
    entry.clusterer = null;
    const parkingMarkers = [];

    for (const zone of state.zones || []) {
      if (!zone.points || zone.points.length < 2) continue;
      let shape;
      if (zone.type === 'line' || zone.points.length < 3) {
        const linePoints = parkingLinePoints(zone.points);
        shape = new ymaps.Polyline(linePoints, {}, {
          strokeColor: zone.candidate ? '#ffffff' : zone.color,
          strokeWidth: zone.candidate ? 9 : 6,
          strokeOpacity: 0.95
        });
      } else {
        shape = new ymaps.Polygon([zone.points], {}, {
          fillColor: zone.color,
          fillOpacity: 0.5,
          strokeColor: zone.candidate ? '#ffffff' : zone.color,
          strokeWidth: zone.candidate ? 4 : 2
        });
      }
      shape.events.add('click', () => entry.onZoneTap(zone.id));
      entry.map.geoObjects.add(shape);
      if (zone.active) {
        if (zone.type === 'line' || zone.points.length < 3) {
          const linePoints = parkingLinePoints(zone.points);
          const outer = new ymaps.Polyline(linePoints, {}, {
            strokeColor: '#ffffff',
            strokeWidth: 10
          });
          const inner = new ymaps.Polyline(linePoints, {}, {
            strokeColor: zone.color,
            strokeWidth: 6
          });
          outer.events.add('click', () => entry.onZoneTap(zone.id));
          inner.events.add('click', () => entry.onZoneTap(zone.id));
          entry.map.geoObjects.add(outer);
          entry.map.geoObjects.add(inner);
        } else {
          const highlight = new ymaps.Polygon([zone.points], {}, {
            fillColor: zone.color,
            fillOpacity: 0.6,
            strokeColor: '#ffffff',
            strokeWidth: 4
          });
          highlight.events.add('click', () => entry.onZoneTap(zone.id));
          entry.map.geoObjects.add(highlight);
        }
      }

      const marker = new ymaps.Placemark(zone.center, {
        parkTrackColor: zone.color,
        parkTrackLabel: zone.label === null ? '' : String(zone.label),
        parkTrackFreeCount: zone.freeCount,
        parkTrackHasForecast: zone.hasForecast
      }, {
        iconLayout: entry.parkingMarkerLayout,
        iconShape: { type: 'Circle', coordinates: [0, 0], radius: 12 },
        zIndex: zone.candidate || zone.active ? 1000 : 500
      });
      marker.events.add('click', () => entry.onZoneTap(zone.id));
      parkingMarkers.push(marker);
    }

    if (parkingMarkers.length > 0) {
      entry.clusterer = new ymaps.Clusterer({
        gridSize: 128,
        maxZoom: 15,
        minClusterSize: 2,
        clusterDisableClickZoom: false,
        clusterOpenBalloonOnClick: false,
        clusterIconLayout: entry.clusterLayout,
        clusterIconShape: { type: 'Circle', coordinates: [0, 0], radius: 14 }
      });
      entry.clusterer.add(parkingMarkers);
      entry.map.geoObjects.add(entry.clusterer);
      styleClusters(entry);
      setTimeout(() => styleClusters(entry), 0);
    }

    if (state.route && state.route.length >= 2) {
      entry.map.geoObjects.add(new ymaps.Polyline(state.route, {}, {
        strokeColor: '#2196f3',
        strokeWidth: 5
      }));
    }
    if (state.user) {
      entry.map.geoObjects.add(new ymaps.Placemark(state.user, {}, {
        iconLayout: entry.userMarkerLayout,
        iconShape: { type: 'Circle', coordinates: [0, 0], radius: 8 }
      }));
    }
    if (state.destination) {
      entry.map.geoObjects.add(new ymaps.Placemark(state.destination, {}, {
        iconLayout: entry.destinationMarkerLayout,
        iconShape: { type: 'Circle', coordinates: [0, 0], radius: 8 }
      }));
    }
    if (state.navigation) {
      entry.map.geoObjects.add(new ymaps.Placemark(
        [state.navigation[0], state.navigation[1]],
        { parkTrackTransform: `rotate(${state.navigation[2]}deg)` },
        {
          iconLayout: entry.navigationMarkerLayout,
          iconShape: { type: 'Rectangle', coordinates: [[-10, -13], [10, 7]] }
        }
      ));
    }
  }

  window.parkTrackYandexMaps = {
    create(elementId, onCamera, onZoneTap) {
      const entry = { map: null, onCamera, onZoneTap, pendingState: null };
      entries.set(elementId, entry);
      if (!window.ymaps) {
        const element = document.getElementById(elementId);
        if (element) {
          element.innerHTML = '<div style="display:flex;height:100%;align-items:center;justify-content:center;padding:24px;text-align:center;font-family:sans-serif">Не удалось загрузить API Яндекс Карт</div>';
        }
        return;
      }
      ymaps.ready(() => {
        if (!entries.has(elementId)) return;
        try {
          entry.parkingMarkerLayout = ymaps.templateLayoutFactory.createClass(
            '<div style="position:absolute;left:-12px;top:-12px;width:24px;height:24px;box-sizing:border-box;border:0.7px solid #fff;border-radius:50%;background:$[properties.parkTrackColor];display:flex;align-items:center;justify-content:center;color:#fff;font-family:Roboto,Arial,sans-serif;font-size:9.5px;font-weight:700;line-height:1">$[properties.parkTrackLabel]</div>'
          );
          entry.clusterLayout = ymaps.templateLayoutFactory.createClass(
            '<div style="position:absolute;left:-14px;top:-14px;width:28px;height:28px;box-sizing:border-box;border:1px solid #fff;border-radius:50%;background:$[properties.parkTrackColor];display:flex;align-items:center;justify-content:center;text-align:center;white-space:pre-line;color:#fff;font-family:Roboto,Arial,sans-serif;font-size:8px;font-weight:700;line-height:1.2">$[properties.parkTrackLabel]</div>'
          );
          entry.userMarkerLayout = ymaps.templateLayoutFactory.createClass(
            '<div style="position:absolute;left:-8px;top:-8px;width:16px;height:16px;box-sizing:border-box;border:1.3px solid #fff;border-radius:50%;background:#007aff"></div>'
          );
          entry.destinationMarkerLayout = ymaps.templateLayoutFactory.createClass(
            '<div style="position:absolute;left:-8px;top:-8px;width:16px;height:16px;box-sizing:border-box;border:1px solid #fff;border-radius:50%;background:#2e7d32"></div>'
          );
          entry.navigationMarkerLayout = ymaps.templateLayoutFactory.createClass(
            '<svg style="position:absolute;left:-13.33px;top:-13.33px;width:26.67px;height:26.67px;filter:drop-shadow(0 0.7px 1.3px #44000000);transform:$[properties.parkTrackTransform]" viewBox="0 0 80 80"><path d="M40 4 L62.4 57.6 L40 44.8 L17.6 57.6 Z" fill="#2e7d32" stroke="#fff" stroke-width="2.5" stroke-linejoin="round"/></svg>'
          );
          entry.map = new ymaps.Map(elementId, {
            center: [61.789114, 34.359757],
            zoom: 14,
            controls: []
          }, {
            suppressMapOpenBlock: true
          });
          entry.map.options.set('suppressMapOpenBlock', true);
          entry.map.container.fitToViewport();
        } catch (error) {
          const element = document.getElementById(elementId);
          if (element) {
            element.innerHTML = '<div style="display:flex;height:100%;align-items:center;justify-content:center;padding:24px;text-align:center;font-family:sans-serif">Не удалось инициализировать Яндекс Карту</div>';
          }
          console.error('Failed to initialize Yandex Maps', error);
          return;
        }
        let timer;
        entry.map.events.add('boundschange', () => {
          clearTimeout(timer);
          timer = setTimeout(() => {
            if (!emitCamera(entry)) entry.map.container.fitToViewport();
            styleClusters(entry);
          }, 100);
        });
        if (entry.pendingState) render(entry, entry.pendingState);
        setTimeout(() => {
          if (!entry.map) return;
          entry.map.container.fitToViewport();
          emitCamera(entry);
        }, 50);
      });
    },

    suggest(text, south, west, north, east) {
      return withYmapsReady(() => {
        const searchControl = new ymaps.control.SearchControl({
          options: {
            provider: 'yandex#search',
            boundedBy: [[south, west], [north, east]],
            results: 10,
            noPopup: true,
            noSuggestPanel: true,
            useMapBounds: false
          }
        });
        return searchControl.search(text).then(
          () => {
            const items = serializeSearchResults(
              searchControl.getResultsArray(),
              text
            );
            searchControl.clear();
            return items.length > 0
              ? items
              : geocodePlaces(text, south, west, north, east);
          },
          () => geocodePlaces(text, south, west, north, east)
        );
      }).then(items => JSON.stringify(items));
    },

    geocode(text, south, west, north, east) {
      return withYmapsReady(() => ymaps.geocode(text, {
        boundedBy: [[south, west], [north, east]],
        results: 1
      })).then(result => {
        const geoObject = result.geoObjects.get(0);
        if (!geoObject) return 'null';
        const coordinates = geoObject.geometry.getCoordinates();
        if (!coordinates || coordinates.length < 2) return 'null';
        return JSON.stringify({
          latitude: coordinates[0],
          longitude: coordinates[1]
        });
      });
    },

    route(fromLatitude, fromLongitude, toLatitude, toLongitude) {
      return withYmapsReady(() => ymaps.route([
        [fromLatitude, fromLongitude],
        [toLatitude, toLongitude]
      ], {
        mapStateAutoApply: false,
        routingMode: 'auto'
      })).then(route => {
        const points = [];
        route.getPaths().each(path => {
          const pathPoints = path.geometry.getCoordinates() || [];
          for (const point of pathPoints) {
            const previous = points[points.length - 1];
            if (!previous || previous[0] !== point[0] || previous[1] !== point[1]) {
              points.push(point);
            }
          }
        });
        const duration = typeof route.getJamsTime === 'function'
          ? route.getJamsTime()
          : typeof route.getTime === 'function' ? route.getTime() : 0;
        const distance = typeof route.getLength === 'function' ? route.getLength() : 0;
        return JSON.stringify({ points, duration, distance });
      });
    },

    update(elementId, stateJson) {
      const entry = entries.get(elementId);
      if (entry) render(entry, JSON.parse(stateJson));
    },

    move(elementId, latitude, longitude, zoom) {
      const entry = entries.get(elementId);
      if (entry && entry.map) entry.map.setCenter([latitude, longitude], zoom, { duration: 300 });
    },

    setZoom(elementId, zoom) {
      const entry = entries.get(elementId);
      if (entry && entry.map) entry.map.setZoom(zoom, { duration: 200 });
    },

    destroy(elementId) {
      const entry = entries.get(elementId);
      if (entry && entry.map) entry.map.destroy();
      entries.delete(elementId);
    }
  };
})();
