<xsl:transform xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
	<xsl:output omit-xml-declaration="yes" indent="yes" />
	<xsl:param name="subsequent" />
	<xsl:param name="buddyIconDirectory" />
	<xsl:param name="buddyIconExtension" />

	<xsl:template match="/">
		<xsl:choose>
			<xsl:when test="$subsequent != 'yes'">
				<xsl:apply-templates />
			</xsl:when>
			<xsl:otherwise>
				<xsl:apply-templates select="/envelope/message[last()]" />
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="event">
		<div class="event">
			<xsl:copy-of select="message/child::node()" />
			<xsl:if test="reason!=''">
				<span class="reason">
					<xsl:text> (</xsl:text>
					<xsl:apply-templates select="reason/child::node()" mode="copy"/>
					<xsl:text>)</xsl:text>
				</span>
			</xsl:if>
		</div>
	</xsl:template>

	<xsl:template match="envelope">
		<xsl:variable name="messageClass">
			<xsl:choose>
				<xsl:when test="sender/@self = 'yes'">
					<xsl:text>selfMessage</xsl:text>
				</xsl:when>
				<xsl:otherwise>
					<xsl:text>message</xsl:text>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>

		<xsl:variable name="bubbleClass">
			<xsl:choose>
				<xsl:when test="sender/@self = 'yes'">
					<xsl:text>rightBubble</xsl:text>
				</xsl:when>
				<xsl:otherwise>
					<xsl:text>leftBubble</xsl:text>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>

		<table id="{@id}" class="{$messageClass}" cellpadding="0" cellspacing="0">
		<tr>
			<xsl:choose>
				<xsl:when test="sender/@self = 'yes'">
					<td class="gutter"></td>
				</xsl:when>
				<xsl:otherwise>
					<td class="icon">
					<xsl:choose>
						<xsl:when test="string-length( sender/@card )">
			     		   <img src="file://{concat( $buddyIconDirectory, sender/@card, $buddyIconExtension )}" width="32" height="32" alt="" onerror="this.src = 'person.tif'" />
						</xsl:when>
						<xsl:otherwise>
			     		   <img src="person.tif" width="32" height="32" alt="" />
						</xsl:otherwise>
					</xsl:choose>
					</td>
				</xsl:otherwise>
			</xsl:choose>
			<td>
				<table class="{$bubbleClass}" cellpadding="0" cellspacing="0">
				<tr>
					<td class="topLeft"></td>
					<td class="center" rowspan="2">
						<div class="text">
						<span>
						<xsl:if test="message[1]/@action = 'yes'">
							<span class="member action"><xsl:value-of select="sender" /></span><xsl:text> </xsl:text>
						</xsl:if>
						<xsl:copy-of select="message[1]/child::node()" />
						</span>
						<xsl:apply-templates select="message[position() &gt; 1]" />
						<xsl:if test="position() = last()">
							<div id="consecutiveInsert" />
						</xsl:if>
						</div>
					</td>
					<td class="topRight"></td>
				</tr>
				<tr>
					<td class="left"></td>
					<td class="right"></td>
				</tr>
				<tr>
					<td class="bottomLeft"></td>
					<td class="bottom"></td>
					<td class="bottomRight"></td>
				</tr>
				</table>
			</td>
			<xsl:choose>
				<xsl:when test="sender/@self = 'yes'">
					<td class="icon">
					<xsl:choose>
						<xsl:when test="string-length( sender/@card )">
			     		   <img src="file://{concat( $buddyIconDirectory, sender/@card, $buddyIconExtension )}" width="32" height="32" alt="" onerror="this.src = 'person.tif'" />
						</xsl:when>
						<xsl:otherwise>
			     		   <img src="person.tif" width="32" height="32" alt="" />
						</xsl:otherwise>
					</xsl:choose>
					</td>
				</xsl:when>
				<xsl:otherwise>
					<td class="gutter" rowspan="2"></td>
				</xsl:otherwise>
			</xsl:choose>
		</tr>
		<xsl:if test="sender/@self != 'yes'">
			<tr>
				<td colspan="2" class="sender"><xsl:value-of select="sender" /></td>
			</tr>
		</xsl:if>
		</table>
	</xsl:template>

	<xsl:template match="message">
		<hr />
		<span>
		<xsl:if test="@action = 'yes'">
			<span class="member action"><xsl:value-of select="../sender" /></span><xsl:text> </xsl:text>
		</xsl:if>
		<xsl:copy-of select="child::node()" /></span>
		<xsl:if test="$subsequent = 'yes'">
			<div id="consecutiveInsert" />
		</xsl:if>
	</xsl:template>
</xsl:transform>
