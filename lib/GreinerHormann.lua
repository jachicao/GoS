-- Source: https://github.com/w8r/GreinerHormann

class "GreinerHormann"
	function GreinerHormann:__init()

	end

	function GreinerHormann:union(polygonA, polygonB)
		return self:clip(polygonA, polygonB, false, false);
	end

	function GreinerHormann:intersection(polygonA, polygonB)
		return self:clip(polygonA, polygonB, true, true);
	end

	function GreinerHormann:diff(polygonA, polygonB)
		return self:clip(polygonA, polygonB, false, true);
	end

	function GreinerHormann:clip(polygonA, polygonB, eA, eB)
		local source = GreinerHormannPolygon(polygonA);
		local clip = GreinerHormannPolygon(polygonB);
		return source:clip(clip, eA, eB);
	end

class "GreinerHormannPolygon"

	function GreinerHormannPolygon:__init(p, arrayVertices)
		self.first = nil;
		self.vertices = 0;
		self._lastUnprocessed = nil;
		self._arrayVertices = nil;

		if not arrayVertices then
			self._arrayVertices = type(p) == "table";
		else
			self._arrayVertices = arrayVertices;
		end

		-- TODO: Check
		for i, point in ipairs(p) do
			self:addVertex(GreinerHormannVertex(point));
		end
	end

	function GreinerHormannPolygon:addVertex(vertex)
		if self.first == nil then
			self.first = vertex;
			self.first.next = vertex;
			self.first.prev = vertex;
		else
			local nxt = self.first;
			local prev = nxt.prev;

			next.prev = vertex;
			vertex.next = next;
			vertex.prev = prev;
			prev.next = vertex;
		end
		self.vertices = self.vertices + 1;
	end

	function GreinerHormannPolygon:insertVertex(vertex, start, end1)
		local prev = start;
		local curr = start;

		while not curr:equals(end1) and curr._distance < vertex._distance do
			curr = curr.next;
		end

		vertex.next = curr;
		prev = curr.prev;

		vertex.prev = prev;
		prev.next = vertex;
		curr.prev = vertex;

		self.vertices = self.vertices + 1;
	end

	function GreinerHormannPolygon:getNext(v)
		local c = v;
		while c._isIntersection do
			c = c.next;
		end
		return c;
	end

	function GreinerHormannPolygon:getFirstIntersect()
		local v = self._firstIntersect and self._firstIntersect or self.first;

		while not v:equals(self.first) do
			if v._isIntersection and not v._visited then
				break;
			end
			v = v.next;
		end

		self._firstIntersect = v;
		return v;
	end

	function GreinerHormannPolygon:hasUnprocessed()
		local v = self._lastUnprocessed and self._lastUnprocessed or self.first;
		while not v:equals(self.first) do
			if v._isIntersection and not v._visited then
				self._lastUnprocessed = v;
				return true;
			end
		end

		self._lastUnprocessed = nil;
		return false;
	end

	function GreinerHormannPolygon:getPoints()
		local points = {};
		local v = self.first;

		if self._arrayVertices then
			while v ~= self.first do
				local t = {};
				table.insert(t, v.x);
				table.insert(t, v.y);
				table.insert(points, t)
				v = v.next;
			end
		else
			while v ~= self.first do
				table.insert(points, {
					x = v.x,
					y = v.y
				})
				v = v.next;
			end
		end
		return points;
	end

	function GreinerHormannPolygon:clip(clip, sourceForwards, clipForwards)
		local sourceVertex = self.first;
		local clipVertex = clip.first;
		local sourceInClip = nil;
		local clipInSource = nil;

		while not sourceVertex:equals(self.first) do
			if not sourceVertex._isIntersection then
				while not sourceVertex:equals(clip.first) do
					if not clipVertex._isIntersection then
						local i = GreinerHormannIntersection(sourceVertex, self:getNext(sourceVertex.next), clipVertex, clip:getNext(clipVertex.next));
						if i:valid() then

						end
					end
					clipVertex = clipVertex.next;
				end
			end

			sourceVertex = sourceVertex.next;
		end

	end

class "GreinerHormannVertex"
	
	function GreinerHormannVertex:__init()

	end

	function GreinerHormannVertex:equals(v)
		return self.x == v.x and self.y == v.y;
	end

class "GreinerHormannIntersection"

	function GreinerHormannIntersection:__init(s1, s2, c1, c2)
		-- body
	end

	function GreinerHormannIntersection:valid()
		return (0 < self.toSource and self.toSource < 1) and (0 < self.toClip and self.toClip < 1);
	end