var animatingScroll = false;
var animationInterval = null;
var startScrollTop = 0;
var currentScrollTop = 0;
var targetScrollTop = 0;
var animationComplete = 0;
var autoscrollSuspended = false;

function animateScroll(target, duration, callback) {
	function cubicInOut(t, b, c, d) {
		if ((t/=d/2) < 1) return c/2*t*t*t + b;
		return c/2*((t-=2)*t*t + 2) + b;
	}

	const slice = (1000 / 30); // 30 frames per second

	animationComplete = 0;
	startScrollTop = currentScrollTop;
	targetScrollTop = target;

	if (animatingScroll) return;

	animatingScroll = true;

	function step() {
		animationComplete += slice;

		if (animationComplete < duration) {
			currentScrollTop = cubicInOut(animationComplete, startScrollTop, targetScrollTop - startScrollTop, duration);
			document.body.scrollTop = currentScrollTop;
		} else {
			currentScrollTop = targetScrollTop;
			document.body.scrollTop = currentScrollTop;

			clearInterval(animationInterval);
			animationInterval = null;

			animatingScroll = false;
			if (callback) callback();
		}
	}

	step();

	animationInterval = setInterval(step, slice);
}

function stopScrollAnimation() {
	clearInterval(animationInterval);
	animationInterval = null;
	animatingScroll = false;
}

function appendComponents(components, previousSession, suppressScroll, suppressScrollAnimation) {
	if (autoscrollSuspended)
		suppressScroll = true;
	var alwaysScroll = false;
	var wasNearBottom = (!suppressScroll && nearBottom());

	var componentsLength = components.length;
	for (var i = 0; i < componentsLength; ++i) {
		var component = components[i];
		if (component.type === "message") {
			if (component.self) alwaysScroll = true;
			appendMessage(component.sender, component.message, component.highlighted, component.action, component.self, true, previousSession);
		} else if (component.type = "event")
			appendEventMessage(component.message, component.identifier, true, previousSession);
	}

	if (!suppressScroll && (alwaysScroll || wasNearBottom))
		scrollToBottom(!suppressScrollAnimation);
}

function appendMessage(senderNickname, messageHTML, highlighted, action, self, suppressScroll, previousSession) {
	if (autoscrollSuspended)
		suppressScroll = true;

	var wasNearBottom = (!suppressScroll && nearBottom());

	var className = "message-wrapper";
	if (action) className += " action";
	if (highlighted) className += " highlight";
	if (previousSession) className += " previous-session";

	var messageWrapperElement = document.createElement("div");
	messageWrapperElement.className = className;

	className = "sender";
	if (self) className += " self";

	var senderElement = document.createElement("div");
	senderElement.className = className;
	senderElement.textContent = senderNickname;
	messageWrapperElement.appendChild(senderElement);

	var messageElement = document.createElement("div");
	messageElement.className = "message";
	messageWrapperElement.appendChild(messageElement);

	document.body.appendChild(messageWrapperElement);

	var range = document.createRange();
	range.selectNode(messageElement);

	var messageFragment = range.createContextualFragment(messageHTML);
	messageElement.appendChild(messageFragment);

	if (!suppressScroll && (alwaysScroll || wasNearBottom))
		scrollToBottom(true);
}

function appendEventMessage(messageHTML, identifier, suppressScroll, previousSession) {
	if (autoscrollSuspended)
		suppressScroll = true;

	var wasNearBottom = (!suppressScroll && nearBottom());

	var className = "event";
	if (identifier) className += " " + identifier;
	if (previousSession) className += " previous-session";

	var eventElement = document.createElement("div");
	eventElement.className = className;

	document.body.appendChild(eventElement);

	var range = document.createRange();
	range.selectNode(eventElement);

	var messageFragment = range.createContextualFragment(messageHTML);
	eventElement.appendChild(messageFragment);

	if (!suppressScroll && wasNearBottom)
		scrollToBottom(!suppressScrollAnimation);
}

function enforceScrollbackLimit() {
	if (document.body.childNodes.length < 300)
		return;
	while (document.body.childNodes.length > 275)
		document.body.removeChild(document.body.firstChild);
	scrollToBottom(false, true);
}

function suspendAutoscroll() {
	autoscrollSuspended = true;
}

function resumeAutoscroll() {
	autoscrollSuspended = false;
}

function updateScrollPosition(position) {
	currentScrollTop = position;
}

function nearBottom() {
	return (animatingScroll || currentScrollTop >= (document.body.scrollHeight - window.innerHeight - 30));
}

function scrollToBottomIfNeeded(animated) {
	if (nearBottom())
		scrollToBottom(animated);
}

function scrollToBottom(animated, suppressEnforceScrollbackLimit) {
	if (!animated) {
		stopScrollAnimation();

		if (!suppressEnforceScrollbackLimit)
			enforceScrollbackLimit();

		currentScrollTop = (document.body.scrollHeight - window.innerHeight);
		document.body.scrollTop = currentScrollTop;
		return;
	}

	function tryEnforcingScrollback() {
		if (!animatingScroll)
			enforceScrollbackLimit();
	}

	function animationFinished() {
		if (!suppressEnforceScrollbackLimit)
			setTimeout(tryEnforcingScrollback, 500);
	}

	var newScrollTop = (document.body.scrollHeight - window.innerHeight);
	animateScroll(newScrollTop, 250, animationFinished);
}

function isDocumentReady() {
	return (document.readyState === "complete");
}
