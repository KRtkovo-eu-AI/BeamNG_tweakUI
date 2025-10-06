angular.module('beamng.apps')
.directive('bell407SurveyingAutopilot', ['$timeout', function ($timeout) {
  return {
    templateUrl: '/ui/modules/apps/bell407SurveyingAutopilot/app.html',
    replace: true,
    restrict: 'EA',
    scope: true,
    controller: ['$scope', '$element', function ($scope, $element) {
      const streamsList = ['sensors', 'electrics']
      StreamsManager.add(streamsList)

      const MAX_INSTALL_CHECK_ATTEMPTS = 3
      const INSTALL_CHECK_RETRY_DELAY = 300
      const VEHICLE_EVENT_INSTALL_CHECK_DELAY = 150
      const MINIMIZE_STORAGE_KEY = 'bell407SurveyUI.minimized'
      const HOME_FETCH_LUA = '(function() local ext = extensions and extensions.surveyingAutopilot if ext and ext.getHome then return ext.getHome() end end)()'

      const defaultParams = {
        altitude: 120,
        angle: 0,
        length: 400,
        spacing: 40,
        rows: 4,
        speed: 18,
        finishMode: 'hover',
        transitSpeed: undefined
      }

      const defaultStatus = {
        state: 'idle',
        planLoaded: false,
        armed: false,
        active: false,
        waypointIndex: 0,
        waypointCount: 0,
        progress: 0,
        finishMode: null,
        target: null,
        planId: null,
        event: null,
        rotorRPM: 0,
        altitude: 0,
        awaitingPatternStart: false
      }

      const patternGeometry = {
        start: null,
        points: [],
        heading: 0,
        home: null,
        mapSegments: [],
        bounds: null
      }

      const stateLabels = {
        idle: 'Idle',
        armed: 'Armed',
        engineStart: 'Engine start',
        spinup: 'Rotor spin-up',
        takeoff: 'Takeoff',
        transitStart: 'Transit to start',
        holding: 'Holding',
        pattern: 'Survey in progress',
        finishHover: 'Hovering',
        returnStart: 'Returning to start',
        returnHome: 'Returning home',
        landing: 'Landing',
        complete: 'Completed'
      }

      $scope.installState = { status: 'checking' }
      $scope.params = angular.copy(defaultParams)
      $scope.finishModes = [
        { value: 'hover', label: 'Hover at final waypoint' },
        { value: 'return_start', label: 'Return to start' },
        { value: 'return_home_land', label: 'Return home and land' }
      ]

      function getFinishModeLabel(value) {
        if (!value) return ''
        const match = ($scope.finishModes || []).find(function (mode) {
          return mode.value === value
        })
        return match ? match.label : value
      }

      $scope.getFinishModeLabel = getFinishModeLabel

      $scope.startPoint = null
      $scope.homePoint = null
      $scope.preview = { altitude: null, speed: null, finishMode: null, rotorRPM: 380, heading: 0, waypoints: [] }
      $scope.previewReady = false
      $scope.previewPending = false
      $scope.previewError = null
      $scope.pending = { arm: false, start: false }
      $scope.status = angular.copy(defaultStatus)
      $scope.statusText = stateLabels.idle
      $scope.spoolPercent = 0
      $scope.vehicle = {
        position: null,
        yaw: 0,
        speed: 0
      }
      $scope.homeStatus = ''
      $scope.homeStatusState = 'info'
      $scope.layout = { compact: false, stacked: false }
      $scope.uiState = { minimized: loadMinimizedState() }
      persistMinimizedState($scope.uiState.minimized)

      let previewDebounce = null
      let lastPreviewSignature = null
      let completionTimer = null
      let resizeObserver = null
      let drawPending = null
      let pendingInstallCheck = null
      let installCheckAttempts = 0
      let homeSyncInFlight = false
      let lastPreviewId = null

      const mapState = {
        canvas: null,
        ctx: null
      }

      function setMinimizedState(value) {
        const next = !!value
        if ($scope.uiState.minimized === next) return
        $scope.uiState.minimized = next
        persistMinimizedState(next)
        if (!next) {
          $timeout(function () {
            ensureCanvasSize()
            scheduleDraw()
          })
        }
      }

      $scope.toggleMinimized = function () {
        setMinimizedState(!$scope.uiState.minimized)
      }

      function loadMinimizedState() {
        try {
          return window.localStorage.getItem(MINIMIZE_STORAGE_KEY) === '1'
        } catch (err) {
          return false
        }
      }

      function persistMinimizedState(minimized) {
        try {
          window.localStorage.setItem(MINIMIZE_STORAGE_KEY, minimized ? '1' : '0')
        } catch (err) {
          // ignore storage errors
        }
      }

      function toNumber(value, fallback) {
        const num = parseFloat(value)
        return Number.isFinite(num) ? num : fallback
      }

      function toArray(value) {
        if (!value) return []
        if (Array.isArray(value)) return value.slice()
        if (typeof value.length === 'number' && Number.isFinite(value.length) && value.length >= 0) {
          try {
            return Array.prototype.slice.call(value)
          } catch (err) {
            // fall back to key-based extraction below
          }
        }
        if (typeof value === 'object') {
          return Object.keys(value)
            .map(function (key) {
              const index = parseInt(key, 10)
              if (!Number.isFinite(index)) return null
              return { key: key, index: index }
            })
            .filter(Boolean)
            .sort(function (a, b) { return a.index - b.index })
            .map(function (entry) { return value[entry.key] })
        }
        return []
      }

      function pickCoordinate(source, keys) {
        for (let i = 0; i < keys.length; i += 1) {
          const key = keys[i]
          if (source[key] !== undefined && source[key] !== null) {
            return source[key]
          }
        }
        return undefined
      }

      function clonePoint(source) {
        if (!source || typeof source !== 'object') return null
        const xVal = pickCoordinate(source, ['x', 'X', 0, '0', 1, '1'])
        const yVal = pickCoordinate(source, ['y', 'Y', 1, '1', 2, '2'])
        const zVal = pickCoordinate(source, ['z', 'Z', 2, '2', 3, '3'])
        return {
          x: toNumber(xVal, 0),
          y: toNumber(yVal, 0),
          z: toNumber(zVal, 0)
        }
      }

      function withFlightAltitude(point, fallbackZ) {
        const clone = clonePoint(point)
        if (!clone) return null
        const reference = fallbackZ !== undefined ? fallbackZ : (clone.z || 0)
        const altitude = toNumber($scope.params && $scope.params.altitude, reference)
        if (Number.isFinite(altitude)) {
          clone.z = altitude
        }
        return clone
      }

      function cloneBounds(source) {
        if (!source || typeof source !== 'object') return null
        const minX = toNumber(source.minX, NaN)
        const maxX = toNumber(source.maxX, NaN)
        const minY = toNumber(source.minY, NaN)
        const maxY = toNumber(source.maxY, NaN)
        if (!Number.isFinite(minX) || !Number.isFinite(maxX) || !Number.isFinite(minY) || !Number.isFinite(maxY)) {
          return null
        }
        return { minX, maxX, minY, maxY }
      }

      function cloneSegment(segment) {
        if (!segment) return null
        let startSource = segment.a || segment[0]
        let endSource = segment.b || segment[1]
        if (!startSource && segment.start) startSource = segment.start
        if (!endSource && segment.finish) endSource = segment.finish
        const start = clonePoint(startSource)
        const finish = clonePoint(endSource)
        if (!start || !finish) return null
        return { a: start, b: finish }
      }

      function applyHomePoint(result, options) {
        const point = clonePoint(result)
        if (!point) {
          if (!options || options.updateStatus !== false) {
            $scope.homeStatus = (options && options.missingMessage) || 'Home position unavailable from autopilot.'
            $scope.homeStatusState = 'error'
          }
          return false
        }

        $scope.homePoint = point

        if ((!$scope.startPoint && (options ? options.setStartIfMissing !== false : true)) || (options && options.forceStart)) {
          const adjusted = withFlightAltitude(point, point.z)
          $scope.startPoint = adjusted || clonePoint(point)
        }

        if (!options || options.updateStatus !== false) {
          if (options && options.message) {
            $scope.homeStatus = options.message
            $scope.homeStatusState = options.state || 'info'
          } else {
            $scope.homeStatus = 'Home position synced from autopilot.'
            $scope.homeStatusState = 'info'
          }
        }

        if (!options || options.queuePreview !== false) {
          queuePreview()
        }
        scheduleDraw()
        return true
      }

      function syncHomeFromAutopilot(options) {
        if ($scope.installState.status !== 'ready') return
        if (homeSyncInFlight && !(options && options.force)) return
        homeSyncInFlight = true
        runOnActive(HOME_FETCH_LUA, function (result) {
          $scope.$evalAsync(function () {
            homeSyncInFlight = false
            const success = applyHomePoint(result, options)
            if (!success && options && typeof options.onFailure === 'function') {
              options.onFailure()
            }
            if (success && options && typeof options.onSuccess === 'function') {
              options.onSuccess()
            }
          })
        })
      }

      function updateStatusText() {
        if ($scope.status.state === 'holding' && $scope.status.awaitingPatternStart) {
          $scope.statusText = 'Holding at start - press Start survey to begin pattern'
          return
        }
        $scope.statusText = stateLabels[$scope.status.state] || ($scope.status.state || 'Unknown')
      }

      function updateSpoolPercent() {
        const target = ($scope.preview && toNumber($scope.preview.rotorRPM, 0)) || 380
        const max = target > 0 ? target : 380
        if (max <= 0) {
          $scope.spoolPercent = 0
          return
        }
        const rpm = toNumber($scope.status.rotorRPM, 0)
        $scope.spoolPercent = Math.max(0, Math.min(100, (rpm / max) * 100))
      }

      function updateVehicleLayout(width, height) {
        const compact = width < 980
        const stacked = width < 720 || height < 360
        if ($scope.layout.compact !== compact || $scope.layout.stacked !== stacked) {
          $scope.layout.compact = compact
          $scope.layout.stacked = stacked
        }
      }

      function ensureCanvasSize() {
        if (!mapState.canvas) return
        const bounds = mapState.canvas.getBoundingClientRect()
        const ratio = window.devicePixelRatio || 1
        const width = Math.max(1, Math.round(bounds.width * ratio))
        const height = Math.max(1, Math.round(bounds.height * ratio))
        if (mapState.canvas.width !== width || mapState.canvas.height !== height) {
          mapState.canvas.width = width
          mapState.canvas.height = height
        }
      }

      function gatherPatternPoints() {
        const points = []
        if (patternGeometry.start) points.push(patternGeometry.start)
        if (patternGeometry.points && patternGeometry.points.length) {
          patternGeometry.points.forEach(function (pt) {
            if (pt) points.push(pt)
          })
        }
        if (patternGeometry.mapSegments && patternGeometry.mapSegments.length) {
          patternGeometry.mapSegments.forEach(function (segment) {
            if (!segment) return
            if (segment.a) points.push(segment.a)
            if (segment.b) points.push(segment.b)
          })
        }
        if ($scope.vehicle.position) points.push($scope.vehicle.position)
        if (patternGeometry.home) points.push(patternGeometry.home)
        if (points.length > 0) return points
        if ($scope.startPoint) return [$scope.startPoint]
        return []
      }

      function scheduleDraw() {
        if (!mapState.ctx || drawPending) return
        if ($scope.uiState.minimized) return
        drawPending = window.requestAnimationFrame(function () {
          drawPending = null
          drawMap()
        })
      }

      function drawMap() {
        if (!mapState.canvas || !mapState.ctx) return
        if ($scope.uiState.minimized) return
        ensureCanvasSize()
        const ratio = window.devicePixelRatio || 1
        const ctx = mapState.ctx
        const width = mapState.canvas.width / ratio
        const height = mapState.canvas.height / ratio

        ctx.save()
        ctx.setTransform(1, 0, 0, 1, 0, 0)
        ctx.clearRect(0, 0, mapState.canvas.width, mapState.canvas.height)
        ctx.scale(ratio, ratio)

        ctx.fillStyle = 'rgba(8, 10, 14, 0.92)'
        ctx.fillRect(0, 0, width, height)

        const points = gatherPatternPoints()
        const bounds = patternGeometry.bounds
        let minX
        let maxX
        let minY
        let maxY
        let padding = 0

        if (bounds && Number.isFinite(bounds.minX) && Number.isFinite(bounds.maxX) && Number.isFinite(bounds.minY) && Number.isFinite(bounds.maxY)) {
          minX = bounds.minX
          maxX = bounds.maxX
          minY = bounds.minY
          maxY = bounds.maxY
        } else if (points.length) {
          minX = points[0].x
          maxX = points[0].x
          minY = points[0].y
          maxY = points[0].y
          points.forEach(function (p) {
            if (!p) return
            if (p.x < minX) minX = p.x
            if (p.x > maxX) maxX = p.x
            if (p.y < minY) minY = p.y
            if (p.y > maxY) maxY = p.y
          })
          padding = Math.max(12, Math.max(maxX - minX, maxY - minY) * 0.2)
          minX -= padding
          maxX += padding
          minY -= padding
          maxY += padding
        } else {
          ctx.restore()
          return
        }

        const spanX = Math.max(maxX - minX, 1)
        const spanY = Math.max(maxY - minY, 1)
        const scale = Math.min(width / spanX, height / spanY)
        const centerX = (minX + maxX) * 0.5
        const centerY = (minY + maxY) * 0.5

        function toScreen(pt) {
          return {
            x: width * 0.5 + (pt.x - centerX) * scale,
            y: height * 0.5 - (pt.y - centerY) * scale
          }
        }

        // draw grid
        const gridSize = Math.pow(10, Math.floor(Math.log10(Math.max(spanX, spanY) / 6)))
        ctx.strokeStyle = 'rgba(120, 140, 160, 0.15)'
        ctx.lineWidth = 1
        ctx.beginPath()
        for (let gx = Math.floor((minX - centerX) / gridSize) * gridSize + centerX - spanX; gx <= maxX + spanX; gx += gridSize) {
          const sx1 = toScreen({ x: gx, y: minY - padding * 0.5 })
          const sx2 = toScreen({ x: gx, y: maxY + padding * 0.5 })
          ctx.moveTo(sx1.x, sx1.y)
          ctx.lineTo(sx2.x, sx2.y)
        }
        for (let gy = Math.floor((minY - centerY) / gridSize) * gridSize + centerY - spanY; gy <= maxY + spanY; gy += gridSize) {
          const sy1 = toScreen({ x: minX - padding * 0.5, y: gy })
          const sy2 = toScreen({ x: maxX + padding * 0.5, y: gy })
          ctx.moveTo(sy1.x, sy1.y)
          ctx.lineTo(sy2.x, sy2.y)
        }
        ctx.stroke()

        if (patternGeometry.mapSegments && patternGeometry.mapSegments.length > 0) {
          const roadWidth = Math.max(0.8, Math.min(3.5, scale * 0.15))
          ctx.strokeStyle = 'rgba(120, 160, 200, 0.5)'
          ctx.lineWidth = roadWidth
          ctx.beginPath()
          patternGeometry.mapSegments.forEach(function (segment) {
            if (!segment || !segment.a || !segment.b) return
            const startScreen = toScreen(segment.a)
            const endScreen = toScreen(segment.b)
            ctx.moveTo(startScreen.x, startScreen.y)
            ctx.lineTo(endScreen.x, endScreen.y)
          })
          ctx.stroke()
        }

        // draw pattern polyline
        if (patternGeometry.points && patternGeometry.points.length > 0) {
          ctx.strokeStyle = 'rgba(100, 220, 255, 0.95)'
          ctx.lineWidth = 2
          ctx.beginPath()
          patternGeometry.points.forEach(function (pt, idx) {
            if (!pt) return
            const screen = toScreen(pt)
            if (idx === 0 && (!patternGeometry.start || (patternGeometry.start.x === pt.x && patternGeometry.start.y === pt.y))) {
              ctx.moveTo(screen.x, screen.y)
            } else if (idx === 0) {
              const startScreen = toScreen(patternGeometry.start)
              ctx.moveTo(startScreen.x, startScreen.y)
              ctx.lineTo(screen.x, screen.y)
            } else {
              ctx.lineTo(screen.x, screen.y)
            }
          })
          ctx.stroke()
        }

        // draw first leg direction arrow
        if (patternGeometry.start && patternGeometry.points.length > 1) {
          const first = toScreen(patternGeometry.start)
          const second = toScreen(patternGeometry.points[1])
          ctx.strokeStyle = 'rgba(138, 255, 210, 0.9)'
          ctx.lineWidth = 3
          ctx.beginPath()
          ctx.moveTo(first.x, first.y)
          ctx.lineTo(second.x, second.y)
          ctx.stroke()

          const dx = second.x - first.x
          const dy = second.y - first.y
          const len = Math.sqrt(dx * dx + dy * dy) || 1
          const ux = dx / len
          const uy = dy / len
          const arrowSize = Math.min(18, len * 0.25)
          ctx.fillStyle = 'rgba(138, 255, 210, 0.9)'
          ctx.beginPath()
          ctx.moveTo(second.x, second.y)
          ctx.lineTo(second.x - ux * arrowSize + uy * arrowSize * 0.6, second.y - uy * arrowSize - ux * arrowSize * 0.6)
          ctx.lineTo(second.x - ux * arrowSize - uy * arrowSize * 0.6, second.y - uy * arrowSize + ux * arrowSize * 0.6)
          ctx.closePath()
          ctx.fill()
        }

        // draw start point
        if (patternGeometry.start) {
          const startScreen = toScreen(patternGeometry.start)
          ctx.fillStyle = '#ffdd57'
          ctx.beginPath()
          ctx.arc(startScreen.x, startScreen.y, 6, 0, Math.PI * 2)
          ctx.fill()
          ctx.fillStyle = 'rgba(255, 220, 120, 0.8)'
          ctx.font = '11px sans-serif'
          ctx.fillText('START', startScreen.x + 8, startScreen.y - 6)
        }

        // draw home point
        const homeToDraw = patternGeometry.home || $scope.homePoint
        if (homeToDraw) {
          const homeScreen = toScreen(homeToDraw)
          ctx.fillStyle = 'rgba(126, 201, 255, 0.95)'
          const size = 6
          ctx.fillRect(homeScreen.x - size, homeScreen.y - size, size * 2, size * 2)
          ctx.fillText('HOME', homeScreen.x + 8, homeScreen.y + 12)
        }

        // draw vehicle icon
        if ($scope.vehicle.position) {
          const vehicleScreen = toScreen($scope.vehicle.position)
          const angle = $scope.vehicle.yaw || 0
          const heading = -angle + Math.PI / 2
          const iconSize = 10
          ctx.fillStyle = 'rgba(255, 110, 110, 0.95)'
          ctx.beginPath()
          ctx.moveTo(vehicleScreen.x + Math.cos(heading) * iconSize, vehicleScreen.y + Math.sin(heading) * iconSize)
          ctx.lineTo(vehicleScreen.x + Math.cos(heading + 2.5) * iconSize * 0.6, vehicleScreen.y + Math.sin(heading + 2.5) * iconSize * 0.6)
          ctx.lineTo(vehicleScreen.x + Math.cos(heading - 2.5) * iconSize * 0.6, vehicleScreen.y + Math.sin(heading - 2.5) * iconSize * 0.6)
          ctx.closePath()
          ctx.fill()
          ctx.fillStyle = 'rgba(255, 160, 160, 0.85)'
          ctx.fillText('YOU', vehicleScreen.x + 8, vehicleScreen.y - 8)
        }

        ctx.restore()
      }

      function updateVehicleSensors(streamData) {
        if (!streamData) return
        const position = streamData.position
        if (position && typeof position.x === 'number') {
          $scope.vehicle.position = {
            x: position.x,
            y: position.y,
            z: position.z || 0
          }
        }
        if (typeof streamData.yaw === 'number') {
          $scope.vehicle.yaw = streamData.yaw
        }
      }

      function updateVehicleElectrics(streamData) {
        if (!streamData) return
        if (typeof streamData.airspeed === 'number') {
          $scope.vehicle.speed = streamData.airspeed
        }
      }

      function updateFromBridgeSnapshot() {
        if (window.bridge && bridge.streams) {
          if (bridge.streams.sensors) updateVehicleSensors(bridge.streams.sensors)
          if (bridge.streams.electrics) updateVehicleElectrics(bridge.streams.electrics)
          scheduleDraw()
        }
      }

      function setInstallState(state) {
        $scope.installState.status = state
      }

      function cancelScheduledInstallCheck() {
        if (pendingInstallCheck) {
          $timeout.cancel(pendingInstallCheck)
          pendingInstallCheck = null
        }
      }

      function scheduleInstallCheck(delay, resetAttempts) {
        if (resetAttempts !== false) {
          installCheckAttempts = 0
        }
        cancelScheduledInstallCheck()
        pendingInstallCheck = $timeout(function () {
          pendingInstallCheck = null
          installCheckAttempts += 1
          setInstallState('checking')
          requestInstallCheck()
        }, typeof delay === 'number' ? delay : 0)
      }

      function runOnActive(command, callback) {
        if (!bngApi || !bngApi.activeObjectLua) {
          if (typeof callback === 'function') callback(null)
          return
        }
        bngApi.activeObjectLua(command, callback)
      }

      function autopilotCommand(fnName, payload, callback) {
        let lua = `extensions.surveyingAutopilot.${fnName}()`
        if (payload !== undefined) {
          try {
            lua = `extensions.surveyingAutopilot.${fnName}(${bngApi.serializeToLua(payload)})`
          } catch (e) {
            console.error('Failed to serialise payload for surveyingAutopilot', e)
          }
        }
        runOnActive(lua, callback)
      }

      function buildPayload() {
        const startSource = $scope.startPoint || $scope.homePoint
        if (!startSource) return null
        const start = clonePoint(startSource)
        if (!start) return null
        const payload = {
          startPoint: start,
          altitude: toNumber($scope.params.altitude, start.z || 0),
          angle: toNumber($scope.params.angle, 0),
          length: toNumber($scope.params.length, 0),
          spacing: toNumber($scope.params.spacing, 0),
          rows: Math.max(1, Math.round(toNumber($scope.params.rows, 1))),
          speed: Math.max(0, toNumber($scope.params.speed, 0)),
          finishMode: $scope.params.finishMode || 'hover'
        }
        const transit = toNumber($scope.params.transitSpeed, NaN)
        if (Number.isFinite(transit) && transit >= 0) {
          payload.transitSpeed = transit
        }
        return payload
      }

      function payloadSignature(payload) {
        if (!payload) return null
        return [
          payload.startPoint && payload.startPoint.x,
          payload.startPoint && payload.startPoint.y,
          payload.startPoint && payload.startPoint.z,
          payload.altitude,
          payload.angle,
          payload.length,
          payload.spacing,
          payload.rows,
          payload.speed,
          payload.finishMode,
          payload.transitSpeed !== undefined ? payload.transitSpeed : 'auto'
        ].join('|')
      }

      function queuePreview() {
        if ($scope.installState.status !== 'ready') return
        if (previewDebounce) {
          $timeout.cancel(previewDebounce)
          previewDebounce = null
        }
        previewDebounce = $timeout(function () {
          previewDebounce = null
          const payload = buildPayload()
          if (!payload) {
            handlePreviewFailure('Select a start point or sync the home position first.')
            return
          }
          const signature = payloadSignature(payload)
          if (signature && signature === lastPreviewSignature && $scope.previewReady) return
          lastPreviewSignature = signature
          $scope.previewPending = true
          $scope.previewError = null
          autopilotCommand('previewPattern', payload, function (result) {
            $scope.$evalAsync(function () {
              if (result === false) {
                handlePreviewFailure('Preview request rejected by autopilot.')
                return
              }
              if (typeof result === 'string') {
                handlePreviewFailure(result)
                return
              }
              if (result && typeof result === 'object') {
                applyPreviewData(result, { force: true })
              }
            })
          })
        }, 180)
      }

      function setPatternGeometryFromPreview(preview) {
        patternGeometry.start = clonePoint(preview.start || $scope.startPoint)
        patternGeometry.points = []
        toArray(preview.waypoints).forEach(function (wp) {
          const point = clonePoint(wp)
          if (point) patternGeometry.points.push(point)
        })
        patternGeometry.heading = toNumber(preview.heading, 0)
        patternGeometry.home = clonePoint(preview.home)
        patternGeometry.bounds = cloneBounds(preview.bounds)
        patternGeometry.mapSegments = []
        toArray(preview.mapSegments).forEach(function (segment) {
          const mapped = cloneSegment(segment)
          if (mapped) patternGeometry.mapSegments.push(mapped)
        })
        if (!patternGeometry.start && patternGeometry.points.length > 0) {
          patternGeometry.start = clonePoint(patternGeometry.points[0])
        }
      }

      function handlePreviewFailure(message) {
        $scope.previewPending = false
        $scope.previewReady = false
        $scope.previewError = message || 'Unable to compute preview.'
        lastPreviewId = null
        patternGeometry.points = []
        patternGeometry.mapSegments = []
        patternGeometry.bounds = null
        scheduleDraw()
      }

      function updatePreviewFromData(data) {
        $scope.previewPending = false
        $scope.previewReady = true
        $scope.previewError = null
        const previewWaypoints = toArray(data.waypoints)
        const previewSegments = toArray(data.mapSegments)
        $scope.preview = {
          altitude: toNumber(data.altitude, $scope.params.altitude),
          speed: toNumber(data.speed, $scope.params.speed),
          finishMode: data.finishMode || $scope.params.finishMode,
          rotorRPM: toNumber(data.rotorRPM, 380),
          heading: toNumber(data.heading, 0),
          waypoints: previewWaypoints,
          start: data.start,
          home: data.home,
          mapSegments: previewSegments,
          bounds: data.bounds,
          planId: data.planId
        }
        if ($scope.preview.finishMode) {
          $scope.params.finishMode = $scope.preview.finishMode
        }
        if (!$scope.startPoint && data.start) {
          $scope.startPoint = clonePoint(data.start)
        }
        if (data.home) {
          const homeClone = clonePoint(data.home)
          if (homeClone) {
            $scope.homePoint = homeClone
            $scope.homeStatus = 'Home position from autopilot.'
            $scope.homeStatusState = 'info'
          }
        }
        setPatternGeometryFromPreview($scope.preview)
        if (!$scope.status.waypointCount && patternGeometry.points.length > 0) {
          $scope.status.waypointCount = Math.max(0, patternGeometry.points.length - 1)
        }
        updateSpoolPercent()
        scheduleDraw()
      }

      function applyPreviewData(data, options) {
        if (!data) return
        if (data.ok === false) {
          lastPreviewId = data.planId || lastPreviewId
          handlePreviewFailure(data.reason)
          return
        }
        if (data.planId && lastPreviewId && data.planId === lastPreviewId && !(options && options.force)) {
          $scope.previewPending = false
          return
        }
        lastPreviewId = data.planId || null
        updatePreviewFromData(data)
      }

      $scope.onParamsChanged = function () {
        queuePreview()
      }

      $scope.useGroundMarker = function () {
        if ($scope.loadingStart) return
        $scope.loadingStart = true
        if (!bngApi || !bngApi.engineLua) {
          $scope.loadingStart = false
          return
        }
        bngApi.engineLua('core_groundMarkers.getTargetPos()', function (result) {
          $scope.$evalAsync(function () {
            $scope.loadingStart = false
            if (result && (result.x || result[1])) {
              const point = withFlightAltitude(result)
              $scope.startPoint = point || clonePoint(result)
              queuePreview()
              scheduleDraw()
            } else {
              $scope.previewError = 'No navigation target selected.'
            }
          })
        })
      }

      $scope.useHomePoint = function () {
        if ($scope.loadingHome) return
        $scope.loadingHome = true
        runOnActive(HOME_FETCH_LUA, function (result) {
          $scope.$evalAsync(function () {
            $scope.loadingHome = false
            applyHomePoint(result)
          })
        })
      }

      $scope.clearStartPoint = function () {
        $scope.startPoint = null
        patternGeometry.start = null
        patternGeometry.points = []
        patternGeometry.mapSegments = []
        patternGeometry.bounds = null
        $scope.previewReady = false
        $scope.previewError = null
        lastPreviewId = null
        scheduleDraw()
      }

      $scope.canArm = function () {
        if ($scope.installState.status !== 'ready') return false
        const payload = buildPayload()
        return !!payload && !$scope.pending.arm
      }

      $scope.canStart = function () {
        if ($scope.installState.status !== 'ready') return false
        if ($scope.pending.start || $scope.pending.arm) return false
        if ($scope.status.armed || $scope.status.state === 'armed') return true
        if ($scope.status.active) {
          return !!$scope.status.awaitingPatternStart
        }
        return !!($scope.startPoint || $scope.homePoint)
      }

      $scope.canAbort = function () {
        return $scope.status.active || $scope.status.armed
      }

      function configureAndArm(afterArm) {
        if ($scope.pending.arm) return false
        const payload = buildPayload()
        if (!payload) {
          $scope.previewError = 'Select a valid start point before arming the autopilot.'
          return false
        }
        $scope.pending.arm = true
        $scope.previewError = null
        autopilotCommand('configurePattern', payload, function (result) {
          $scope.$evalAsync(function () {
            if (result === false) {
              $scope.previewError = 'Failed to configure autopilot pattern.'
              $scope.pending.arm = false
              if (typeof afterArm === 'function') afterArm(false)
              return
            }
            autopilotCommand('activate', undefined, function (activateResult) {
              $scope.$evalAsync(function () {
                if (activateResult === false) {
                  $scope.previewError = 'Autopilot failed to arm.'
                }
                $scope.pending.arm = false
                if (typeof afterArm === 'function') {
                  afterArm(activateResult !== false)
                }
              })
            })
          })
        })
        return true
      }

      $scope.armAutopilot = function () {
        if (!$scope.canArm()) return
        configureAndArm()
      }

      $scope.startSurvey = function () {
        if ($scope.pending.start) return
        const launch = function () {
          $scope.pending.start = true
          autopilotCommand('startSurvey', undefined, function (result) {
            $scope.$evalAsync(function () {
              if (result === false) {
                $scope.previewError = 'Autopilot refused to start the survey.'
              }
              $scope.pending.start = false
            })
          })
        }

        if ($scope.status.state !== 'armed' && !$scope.status.armed) {
          configureAndArm(function (success) {
            if (success) {
              launch()
            }
          })
          return
        }

        launch()
      }

      $scope.abortSurvey = function () {
        autopilotCommand('cancel', 'uiAbort')
        $scope.pending.arm = false
        $scope.pending.start = false
      }

      $scope.resetUi = function () {
        const preservedHome = clonePoint($scope.homePoint)
        $scope.params = angular.copy(defaultParams)
        $scope.startPoint = null
        $scope.previewReady = false
        $scope.preview = { altitude: null, speed: null, finishMode: null, rotorRPM: 380, heading: 0, waypoints: [] }
        patternGeometry.start = null
        patternGeometry.points = []
        patternGeometry.mapSegments = []
        patternGeometry.bounds = null
        patternGeometry.heading = 0
        patternGeometry.home = preservedHome
        $scope.status = angular.copy(defaultStatus)
        $scope.statusText = stateLabels.idle
        $scope.spoolPercent = 0
        $scope.previewError = null
        $scope.pending.arm = false
        $scope.pending.start = false
        lastPreviewSignature = null
        lastPreviewId = null
        scheduleDraw()
      }

      function handleCompletionReset() {
        if (completionTimer) return
        completionTimer = $timeout(function () {
          completionTimer = null
          $scope.status = angular.copy(defaultStatus)
          $scope.statusText = stateLabels.idle
          updateSpoolPercent()
        }, 2000)
      }

      function requestInstallCheck() {
        runOnActive('extensions.surveyingAutopilot and extensions.surveyingAutopilot.isInstalled()', function (result) {
          $scope.$evalAsync(function () {
            if (result) {
              installCheckAttempts = 0
              cancelScheduledInstallCheck()
              setInstallState('ready')
              syncHomeFromAutopilot({ setStartIfMissing: !$scope.startPoint })
              queuePreview()
            } else if (installCheckAttempts < MAX_INSTALL_CHECK_ATTEMPTS) {
              scheduleInstallCheck(INSTALL_CHECK_RETRY_DELAY, false)
            } else {
              installCheckAttempts = 0
              setInstallState('missing')
            }
          })
        })
      }

      $scope.$on('bell407SurveyInstallState', function (event, data) {
        if (data && data.module && data.module !== 'surveyingAutopilot') return
        $scope.$evalAsync(function () {
          const installedFlag = data && typeof data.installed === 'boolean' ? data.installed : null
          if (installedFlag === true) {
            cancelScheduledInstallCheck()
            installCheckAttempts = 0
            if ($scope.installState.status !== 'ready') {
              setInstallState('ready')
            }
            syncHomeFromAutopilot({ setStartIfMissing: !$scope.startPoint })
            queuePreview()
          } else if (installedFlag === false) {
            cancelScheduledInstallCheck()
            installCheckAttempts = 0
            $scope.resetUi()
            setInstallState('missing')
          } else {
            scheduleInstallCheck(INSTALL_CHECK_RETRY_DELAY)
          }
        })
      })

      $scope.$on('bell407SurveyPreview', function (event, data) {
        $scope.$evalAsync(function () {
          applyPreviewData(data)
        })
      })

      $scope.$on('bell407SurveyStatus', function (event, data) {
        if (!data) return
        $scope.$evalAsync(function () {
          angular.extend($scope.status, data)
          if (data.event === null) {
            $scope.status.event = null
          }
          updateStatusText()
          updateSpoolPercent()
          if (!$scope.status.active && !$scope.status.armed) {
            $scope.pending.start = false
            if ($scope.status.state === 'idle') {
              $scope.pending.arm = false
            }
            if ($scope.status.state === 'complete') {
              handleCompletionReset()
            }
          }
          if (data.event && (data.event.type === 'init' || data.event.type === 'reset')) {
            syncHomeFromAutopilot({ setStartIfMissing: !$scope.startPoint, updateStatus: false })
          }
          scheduleDraw()
        })
      })

      $scope.$watch('startPoint', function (value) {
        if (value) {
          patternGeometry.start = clonePoint(value)
          queuePreview()
        }
        scheduleDraw()
      }, true)

      $scope.$watchGroup([
        'params.altitude',
        'params.angle',
        'params.length',
        'params.spacing',
        'params.rows',
        'params.speed',
        'params.finishMode',
        'params.transitSpeed'
      ], function () {
        queuePreview()
      })

      $scope.$on('streamsUpdate', function (event, streams) {
        $scope.$evalAsync(function () {
          if (streams.sensors) updateVehicleSensors(streams.sensors)
          if (streams.electrics) updateVehicleElectrics(streams.electrics)
          scheduleDraw()
        })
      })

      $scope.$on('VehicleChange', function () {
        $scope.$evalAsync(function () {
          $scope.homePoint = null
          patternGeometry.home = null
          $scope.homeStatus = ''
          $scope.homeStatusState = 'info'
          $scope.resetUi()
          scheduleInstallCheck(VEHICLE_EVENT_INSTALL_CHECK_DELAY)
        })
      })

      $scope.$on('VehicleReset', function () {
        $scope.$evalAsync(function () {
          scheduleInstallCheck(VEHICLE_EVENT_INSTALL_CHECK_DELAY)
          syncHomeFromAutopilot({ setStartIfMissing: !$scope.startPoint, force: true })
        })
      })

      scheduleInstallCheck(0)
      updateFromBridgeSnapshot()

      $timeout(function () {
        const host = $element[0]
        const canvas = host.querySelector('.pattern-canvas')
        if (canvas) {
          mapState.canvas = canvas
          mapState.ctx = canvas.getContext('2d')
          ensureCanvasSize()
        }
        if (window.ResizeObserver) {
          resizeObserver = new ResizeObserver(function (entries) {
            entries.forEach(function (entry) {
              const rect = entry.contentRect
              updateVehicleLayout(rect.width, rect.height)
              ensureCanvasSize()
              scheduleDraw()
            })
          })
          resizeObserver.observe(host)
        } else {
          updateVehicleLayout(host.clientWidth, host.clientHeight)
        }
        scheduleDraw()
      })

      $scope.$on('$destroy', function () {
        StreamsManager.remove(streamsList)
        if (previewDebounce) {
          $timeout.cancel(previewDebounce)
        }
        if (completionTimer) {
          $timeout.cancel(completionTimer)
        }
        if (resizeObserver && resizeObserver.disconnect) {
          resizeObserver.disconnect()
        }
        if (drawPending) {
          window.cancelAnimationFrame(drawPending)
          drawPending = null
        }
        if (pendingInstallCheck) {
          $timeout.cancel(pendingInstallCheck)
          pendingInstallCheck = null
        }
      })
    }]
  }
}])
