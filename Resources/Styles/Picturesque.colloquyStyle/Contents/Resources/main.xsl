<xsl:transform xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
	<xsl:output omit-xml-declaration="yes" indent="no" />
	<xsl:param name="subsequent" />

	<xsl:template match="/">
		<xsl:choose>
			<xsl:when test="$subsequent != 'yes'">
				<xsl:apply-templates />
			</xsl:when>
			<xsl:otherwise>
				<xsl:apply-templates select="/envelope/message[last()]" mode="subsequent" />
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="message" mode="subsequent">
		<div>
			<xsl:if test="@action = 'yes'">
				<xsl:text>&#8226; </xsl:text>
				<xsl:value-of select="../sender" />
				<xsl:text> </xsl:text>
			</xsl:if>
			<xsl:apply-templates select="." />
		</div>
		<xsl:if test="$subsequent = 'yes'">
			<div id="consecutiveInsert" />
		</xsl:if>
	</xsl:template>

	<xsl:template match="envelope">
		<xsl:variable name="envelopeClasses">
			<xsl:choose>
				<xsl:when test="message[1]/@action = 'yes'">
					<xsl:text>envelope action</xsl:text>
				</xsl:when>
				<xsl:otherwise>
					<xsl:text>envelope</xsl:text>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>

		<xsl:variable name="senderClasses">
			<xsl:choose>
				<xsl:when test="message[1]/@highlight = 'yes'">
					<xsl:text>header highlight</xsl:text>
				</xsl:when>
				<xsl:when test="sender/@self = 'yes'">
					<xsl:text>header light</xsl:text>
				</xsl:when>
				<xsl:otherwise>
					<xsl:text>header</xsl:text>
				</xsl:otherwise>
			</xsl:choose>
		</xsl:variable>

		<div id="{@id}" class="{$envelopeClasses}">
			<div class="{$senderClasses}">
				<xsl:value-of select="sender" />
				<xsl:text> | </xsl:text>
				<xsl:call-template name="short-time">
					<xsl:with-param name="date" select="message[1]/@received" />
				</xsl:call-template>
			</div>
			<div class="body">
				<xsl:apply-templates select="message" mode="subsequent" />
				<xsl:if test="position() = last()">
					<div id="consecutiveInsert" />
				</xsl:if>
			</div>
		</div>
	</xsl:template>

	<xsl:template match="event">
		<div class="event">
			<xsl:copy-of select="message/child::node()" />
		</div>
	</xsl:template>

	<xsl:template match="a">
		<xsl:variable name="extension" select="substring(@href,string-length(@href) - 3, 4)" />
		<xsl:variable name="extensionLong" select="substring(@href,string-length(@href) - 4, 5)" />

		<xsl:choose>
			<xsl:when test="$extension = '.jpg' or $extension = '.JPG' or $extensionLong = '.jpeg' or $extensionLong = '.JPEG'">
				<a href="{@href}"><img src="{@href}" onload="resizeIfNeeded( this )" /></a>
			</xsl:when>
			<xsl:when test="$extension = '.gif' or $extension = '.GIF'">
				<a href="{@href}"><img src="{@href}" onload="resizeIfNeeded( this )" /></a>
			</xsl:when>
			<xsl:when test="$extension = '.png' or $extension = '.PNG'">
				<a href="{@href}"><img src="{@href}" onload="resizeIfNeeded( this )" /></a>
			</xsl:when>
			<xsl:when test="$extension = '.tif' or $extension = '.TIF' or $extensionLong = '.tiff' or $extensionLong = '.TIFF'">
				<a href="{@href}"><img src="{@href}" onload="resizeIfNeeded( this )" /></a>
			</xsl:when>
			<xsl:when test="$extension = '.bmp' or $extension = '.BMP'">
				<a href="{@href}"><img src="{@href}" onload="resizeIfNeeded( this )" /></a>
			</xsl:when>
	<!--    <xsl:when test="$extension = '.mp3' or $extension = '.m4a' or $extension = '.MP3' or $extension = '.M4A'">
				<embed controller="true" src="{@href}" height="18" width="150" align="absmiddle" type="video/quicktime"></embed>
			</xsl:when> -->
			<xsl:otherwise>
				<xsl:copy-of select="current()"/>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>

	<xsl:template match="b">
		<xsl:copy-of select="current()"/>
	</xsl:template>

	<xsl:template match="u">
		<xsl:copy-of select="current()"/>
	</xsl:template>

	<xsl:template match="i">
		<xsl:copy-of select="current()"/>
	</xsl:template>

	<xsl:template match="font">
		<xsl:copy-of select="current()"/>
	</xsl:template>

	<xsl:template match="span">
		<xsl:copy-of select="current()"/>
	</xsl:template>

	<xsl:template name="short-time">
		<xsl:param name="date" /> <!-- YYYY-MM-DD HH:MM:SS +/-HHMM -->
		<xsl:choose>
			<xsl:when test="number(substring($date, 12, 2)) &gt; 12">
				<xsl:value-of select="number(substring($date, 12, 2)) - 12" />
			</xsl:when>
			<xsl:when test="number(substring($date, 12, 2)) = 0">
				<xsl:text>12</xsl:text>
			</xsl:when>
			<xsl:otherwise>
				<xsl:value-of select="number(substring($date, 12, 2))" />
			</xsl:otherwise>
		</xsl:choose>
		<xsl:text>:</xsl:text>
		<xsl:value-of select="substring($date, 15, 2)" />
		<xsl:choose>
			<xsl:when test="number(substring($date, 12, 2)) &gt;= 12">
				<xsl:text>p</xsl:text>
			</xsl:when>
			<xsl:otherwise>
				<xsl:text>a</xsl:text>
			</xsl:otherwise>
		</xsl:choose>
	</xsl:template>
</xsl:transform>
