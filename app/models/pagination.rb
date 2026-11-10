class Pagination < Data.define(:page, :per, :total)
  def pages = [ (total + per - 1) / per, 1 ].max
  def offset = (page - 1) * per
  def previous = (page - 1 if page > 1)
  def next = (page + 1 if page < pages)

  # Page numbers to link to, with nil standing for a gap: [1, nil, 4, 5, 6, nil, 12]
  def window(around = 2)
    shown = ([ 1, pages ] + ((page - around)..(page + around)).to_a).select { it.between?(1, pages) }.uniq.sort
    shown.each_cons(2).flat_map { |a, b| b - a > 1 ? [ a, nil ] : [ a ] } + [ shown.last ]
  end
end
